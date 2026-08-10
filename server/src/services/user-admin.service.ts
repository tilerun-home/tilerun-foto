import { BadRequestException, ForbiddenException, Injectable } from '@nestjs/common';
import { SALT_ROUNDS } from 'src/constants';
import { AssetStatsDto, AssetStatsResponseDto, mapStats } from 'src/dtos/asset.dto';
import { AuthDto } from 'src/dtos/auth.dto';
import { CalendarHeatmapDto, CalendarHeatmapResponseDto } from 'src/dtos/calendar-heatmap.dto';
import { SessionResponseDto, mapSession } from 'src/dtos/session.dto';
import { UserPreferencesResponseDto, UserPreferencesUpdateDto, mapPreferences } from 'src/dtos/user-preferences.dto';
import {
  UserAdminCreateDto,
  UserAdminDeleteDto,
  UserAdminResponseDto,
  UserAdminSearchDto,
  UserAdminUpdateDto,
  mapUserAdmin,
} from 'src/dtos/user.dto';
import { AlbumUserRole, JobName, UserMetadataKey, UserStatus } from 'src/enum';
import { UserFindOptions } from 'src/repositories/user.repository';
import { BaseService } from 'src/services/base.service';
import { getCalendarHeatmap } from 'src/services/shared/user-methods';
import { getPreferences, getPreferencesPartial, mergePreferences } from 'src/utils/preferences';

@Injectable()
export class UserAdminService extends BaseService {
  async syncTileRunUsers(dto: {
    home?: { id: string; name: string };
    users: { email: string; name: string; isAdmin?: boolean }[];
    revoke: string[];
  }): Promise<{
    created: number;
    updated: number;
    unchanged: number;
    sessionsRevoked: number;
    missing: number;
    familyAlbum: { id: string; name: string; created: boolean; membersAdded: number; membersRemoved: number } | null;
  }> {
    let created = 0;
    let updated = 0;
    let unchanged = 0;
    let sessionsRevoked = 0;
    let missing = 0;
    const syncedUsers = [];

    for (const item of dto.users) {
      const email = item.email.trim().toLowerCase();
      const existing = await this.userRepository.getByEmail(email);
      if (!existing) {
        const user = await this.createUser({ email, name: item.name.trim(), isAdmin: !!item.isAdmin });
        await this.userRepository.upsertMetadata(user.id, {
          key: UserMetadataKey.Onboarding,
          value: { isOnboarded: true },
        });
        syncedUsers.push(user);
        created++;
        continue;
      }

      const changes: { name?: string; isAdmin?: boolean; updatedAt?: Date } = {};
      if (existing.name !== item.name.trim()) {
        changes.name = item.name.trim();
      }
      if (existing.isAdmin !== !!item.isAdmin) {
        changes.isAdmin = !!item.isAdmin;
      }
      if (Object.keys(changes).length > 0) {
        changes.updatedAt = new Date();
        await this.userRepository.update(existing.id, changes);
        updated++;
      } else {
        unchanged++;
      }
      await this.userRepository.upsertMetadata(existing.id, {
        key: UserMetadataKey.Onboarding,
        value: { isOnboarded: true },
      });
      syncedUsers.push(existing);
    }

    for (const rawEmail of dto.revoke) {
      const user = await this.userRepository.getByEmail(rawEmail.trim().toLowerCase());
      if (!user) {
        missing++;
        continue;
      }
      const sessions = await this.sessionRepository.getByUserId(user.id);
      if (sessions.length === 0) {
        continue;
      }
      await this.sessionRepository.invalidateAll({ userId: user.id });
      for (const session of sessions) {
        await this.eventRepository.emit('SessionDelete', { sessionId: session.id });
      }
      sessionsRevoked += sessions.length;
    }

    const familyAlbum = await this.syncTileRunFamilyAlbum(dto.home, syncedUsers);
    return { created, updated, unchanged, sessionsRevoked, missing, familyAlbum };
  }

  private async syncTileRunFamilyAlbum(
    home: { id: string; name: string } | undefined,
    users: { id: string; isAdmin: boolean }[],
  ): Promise<{ id: string; name: string; created: boolean; membersAdded: number; membersRemoved: number } | null> {
    if (!home || users.length === 0) {
      return null;
    }

    const owner = users.find(({ isAdmin }) => isAdmin) ?? (await this.userRepository.getAdmin());
    if (!owner) {
      throw new BadRequestException('TileRun family album requires an administrator');
    }

    const albumName = `Gezin \u00b7 ${home.name}`;
    const marker = `TileRun Home: ${home.id}`;
    const ownedAlbums = await this.albumRepository.getAll(owner.id, { isOwned: true });
    const markedAlbums = ownedAlbums
      .filter(({ description }) => description?.split('\n').includes(marker))
      .sort((left, right) => new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime());
    if (markedAlbums.length > 1) {
      this.logger.warn(`Multiple TileRun family albums found for ${home.id}; using oldest album ${markedAlbums[0].id}`);
    }
    let album = markedAlbums[0];
    let albumCreated = false;
    if (!album) {
      album = await this.albumRepository.create(
        {
          albumName,
          description: `${marker}\nAlleen foto's die een gezinslid bewust aan dit album toevoegt, worden gedeeld.`,
          albumThumbnailAssetId: null,
        },
        [],
        [
          { userId: owner.id, role: AlbumUserRole.Owner },
          ...users.filter(({ id }) => id !== owner.id).map(({ id }) => ({ userId: id, role: AlbumUserRole.Editor })),
        ],
        owner.id,
      );
      albumCreated = true;
    }

    const detailed = albumCreated
      ? album
      : await this.albumRepository.getById(album.id, { withAssets: false }, owner.id);
    if (!detailed) {
      throw new BadRequestException('TileRun family album could not be loaded');
    }
    if (!albumCreated && detailed.albumName !== albumName) {
      await this.albumRepository.update(detailed.id, { albumName }, owner.id);
    }
    const desiredIds = new Set(users.map(({ id }) => id));
    const albumUsers = detailed.albumUsers ?? [];
    const memberships = new Map(albumUsers.map(({ user, role }) => [user.id, role]));
    let membersAdded = 0;
    let membersRemoved = 0;

    for (const user of users) {
      if (user.id === owner.id) {
        continue;
      }
      const role = memberships.get(user.id);
      if (!role) {
        await this.albumUserRepository.create({ albumId: detailed.id, userId: user.id, role: AlbumUserRole.Editor });
        membersAdded++;
      } else if (role !== AlbumUserRole.Editor) {
        await this.albumUserRepository.update(
          { albumId: detailed.id, userId: user.id },
          { role: AlbumUserRole.Editor },
        );
      }
    }

    for (const { user, role } of albumUsers) {
      if (role !== AlbumUserRole.Owner && !desiredIds.has(user.id)) {
        await this.albumUserRepository.delete({ albumId: detailed.id, userId: user.id });
        membersRemoved++;
      }
    }

    return { id: detailed.id, name: albumName, created: albumCreated, membersAdded, membersRemoved };
  }

  async search(auth: AuthDto, dto: UserAdminSearchDto): Promise<UserAdminResponseDto[]> {
    const users = await this.userRepository.getList({
      id: dto.id,
      withDeleted: dto.withDeleted,
    });
    return users.map((user) => mapUserAdmin(user));
  }

  async create(dto: UserAdminCreateDto): Promise<UserAdminResponseDto> {
    const { notify, ...userDto } = dto;
    const config = await this.getConfig({ withCache: false });
    if (!config.oauth.enabled && !userDto.password) {
      throw new BadRequestException('password is required');
    }

    const user = await this.createUser(userDto);

    await this.eventRepository.emit('UserSignup', {
      notify: !!notify,
      id: user.id,
      password: userDto.password,
    });

    return mapUserAdmin(user);
  }

  async get(auth: AuthDto, id: string): Promise<UserAdminResponseDto> {
    const user = await this.findOrFail(id, { withDeleted: true });
    return mapUserAdmin(user);
  }

  async update(auth: AuthDto, id: string, dto: UserAdminUpdateDto): Promise<UserAdminResponseDto> {
    const user = await this.findOrFail(id, {});

    if (dto.isAdmin !== undefined && dto.isAdmin !== auth.user.isAdmin && auth.user.id === id) {
      throw new BadRequestException('Admin status can only be changed by another admin');
    }

    if (dto.quotaSizeInBytes && user.quotaSizeInBytes !== dto.quotaSizeInBytes) {
      await this.userRepository.syncUsage(id);
    }

    if (dto.email) {
      const duplicate = await this.userRepository.getByEmail(dto.email);
      if (duplicate && duplicate.id !== id) {
        this.logger.debug('Email already in use by another account');
        throw new BadRequestException('Email is not available');
      }
    }

    if (dto.storageLabel) {
      const duplicate = await this.userRepository.getByStorageLabel(dto.storageLabel);
      if (duplicate && duplicate.id !== id) {
        throw new BadRequestException('Storage label already in use by another account');
      }
    }

    if (dto.password) {
      dto.password = await this.cryptoRepository.hashBcrypt(dto.password, SALT_ROUNDS);
    }

    if (dto.pinCode) {
      dto.pinCode = await this.cryptoRepository.hashBcrypt(dto.pinCode, SALT_ROUNDS);
    }

    if (dto.storageLabel === '') {
      dto.storageLabel = null;
    }

    const updatedUser = await this.userRepository.update(id, { ...dto, updatedAt: new Date() });

    return mapUserAdmin(updatedUser);
  }

  async delete(auth: AuthDto, id: string, dto: UserAdminDeleteDto): Promise<UserAdminResponseDto> {
    const { force } = dto;
    await this.findOrFail(id, {});
    if (auth.user.id === id) {
      throw new ForbiddenException('Cannot delete your own account');
    }

    await this.albumRepository.softDeleteAll(id);

    const status = force ? UserStatus.Removing : UserStatus.Deleted;
    const user = await this.userRepository.update(id, { status, deletedAt: new Date() });

    await this.eventRepository.emit('UserTrash', user);

    if (force) {
      await this.jobRepository.queue({ name: JobName.UserDelete, data: { id: user.id, force } });
    }

    return mapUserAdmin(user);
  }

  async restore(auth: AuthDto, id: string): Promise<UserAdminResponseDto> {
    await this.findOrFail(id, { withDeleted: true });
    await this.albumRepository.restoreAll(id);
    const user = await this.userRepository.restore(id);
    await this.eventRepository.emit('UserRestore', user);
    return mapUserAdmin(user);
  }

  async getCalendarHeatmap(auth: AuthDto, id: string, dto: CalendarHeatmapDto): Promise<CalendarHeatmapResponseDto> {
    await this.findOrFail(id, { withDeleted: false });
    return getCalendarHeatmap(id, dto, { asset: this.assetRepository });
  }

  async getSessions(auth: AuthDto, id: string): Promise<SessionResponseDto[]> {
    const sessions = await this.sessionRepository.getByUserId(id);
    return sessions.map((session) => mapSession(session));
  }

  async deleteSessions(id: string): Promise<void> {
    await this.findOrFail(id, {});
    const sessions = await this.sessionRepository.getByUserId(id);
    await this.sessionRepository.invalidateAll({ userId: id });
    for (const session of sessions) {
      await this.eventRepository.emit('SessionDelete', { sessionId: session.id });
    }
  }

  async getStatistics(auth: AuthDto, id: string, dto: AssetStatsDto): Promise<AssetStatsResponseDto> {
    const stats = await this.assetRepository.getStatistics(id, dto);
    return mapStats(stats);
  }

  async getPreferences(auth: AuthDto, id: string): Promise<UserPreferencesResponseDto> {
    await this.findOrFail(id, { withDeleted: true });
    const metadata = await this.userRepository.getMetadata(id);
    return mapPreferences(getPreferences(metadata));
  }

  async updatePreferences(auth: AuthDto, id: string, dto: UserPreferencesUpdateDto) {
    await this.findOrFail(id, { withDeleted: false });
    const metadata = await this.userRepository.getMetadata(id);
    const newPreferences = mergePreferences(getPreferences(metadata), dto);

    await this.userRepository.upsertMetadata(id, {
      key: UserMetadataKey.Preferences,
      value: getPreferencesPartial(newPreferences),
    });

    return mapPreferences(newPreferences);
  }

  private async findOrFail(id: string, options: UserFindOptions) {
    const user = await this.userRepository.get(id, options);
    if (!user) {
      throw new BadRequestException('User not found');
    }
    return user;
  }
}
