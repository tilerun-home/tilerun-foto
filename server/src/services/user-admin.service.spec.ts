import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { mapUserAdmin } from 'src/dtos/user.dto';
import { AlbumUserRole, JobName, UserMetadataKey, UserStatus } from 'src/enum';
import { UserAdminService } from 'src/services/user-admin.service';
import { AuthFactory } from 'test/factories/auth.factory';
import { UserFactory } from 'test/factories/user.factory';
import { authStub } from 'test/fixtures/auth.stub';
import { userStub } from 'test/fixtures/user.stub';
import { newTestService, ServiceMocks } from 'test/utils';
import { describe } from 'vitest';

describe(UserAdminService.name, () => {
  let sut: UserAdminService;
  let mocks: ServiceMocks;

  beforeEach(() => {
    ({ sut, mocks } = newTestService(UserAdminService));

    mocks.user.get.mockImplementation((userId) =>
      Promise.resolve([userStub.admin, userStub.user1].find((user) => user.id === userId) ?? undefined),
    );
  });

  describe('syncTileRunUsers', () => {
    it('pre-provisions a user without a separate password', async () => {
      mocks.user.getByEmail.mockResolvedValue(undefined);
      mocks.user.getAdmin.mockResolvedValue(userStub.admin);
      mocks.user.create.mockResolvedValue(userStub.user1);
      mocks.event.emit.mockResolvedValue();

      const result = await sut.syncTileRunUsers({
        users: [{ email: userStub.user1.email, name: userStub.user1.name, isAdmin: false }],
        revoke: [],
      });

      expect(mocks.user.create).toHaveBeenCalledWith({
        email: userStub.user1.email,
        name: userStub.user1.name,
        isAdmin: false,
      });
      expect(result.created).toBe(1);
      expect(mocks.user.upsertMetadata).toHaveBeenCalledWith(userStub.user1.id, {
        key: UserMetadataKey.Onboarding,
        value: { isOnboarded: true },
      });
    });

    it('creates one empty shared family album for all provisioned users', async () => {
      mocks.user.getByEmail.mockImplementation(async (email) =>
        email === userStub.admin.email ? userStub.admin : userStub.user1,
      );
      mocks.album.getAll.mockResolvedValue([]);
      mocks.album.create.mockResolvedValue({
        id: 'family-album',
        albumUsers: [
          { user: userStub.admin, role: AlbumUserRole.Owner },
          { user: userStub.user1, role: AlbumUserRole.Editor },
        ],
      } as never);

      const result = await sut.syncTileRunUsers({
        home: { id: 'home-1', name: 'Bolsius Pedraza' },
        users: [
          { email: userStub.admin.email, name: userStub.admin.name, isAdmin: true },
          { email: userStub.user1.email, name: userStub.user1.name, isAdmin: false },
        ],
        revoke: [],
      });

      expect(mocks.album.create).toHaveBeenCalledWith(
        expect.objectContaining({ albumName: 'Gezin · Bolsius Pedraza', albumThumbnailAssetId: null }),
        [],
        [
          { userId: userStub.admin.id, role: AlbumUserRole.Owner },
          { userId: userStub.user1.id, role: AlbumUserRole.Editor },
        ],
        userStub.admin.id,
      );
      expect(result.familyAlbum).toEqual(
        expect.objectContaining({ id: 'family-album', created: true, membersAdded: 0, membersRemoved: 0 }),
      );
    });

    it('renames the marked family album without creating a duplicate or changing members', async () => {
      mocks.user.getByEmail.mockImplementation(async (email) =>
        email === userStub.admin.email ? userStub.admin : userStub.user1,
      );
      mocks.album.getAll.mockResolvedValue([
        {
          id: 'family-album',
          albumName: 'Gezin · Oude naam',
          description: 'TileRun Home: home-1\nBewuste gezinsdeling.',
          createdAt: new Date('2026-01-01T00:00:00Z'),
        },
      ] as never);
      mocks.album.getById.mockResolvedValue({
        id: 'family-album',
        albumName: 'Gezin · Oude naam',
        albumUsers: [
          { user: userStub.admin, role: AlbumUserRole.Owner },
          { user: userStub.user1, role: AlbumUserRole.Editor },
        ],
      } as never);
      mocks.album.update.mockResolvedValue({ id: 'family-album' } as never);

      const result = await sut.syncTileRunUsers({
        home: { id: 'home-1', name: 'Nieuwe naam' },
        users: [
          { email: userStub.admin.email, name: userStub.admin.name, isAdmin: true },
          { email: userStub.user1.email, name: userStub.user1.name, isAdmin: false },
        ],
        revoke: [],
      });

      expect(mocks.album.update).toHaveBeenCalledWith(
        'family-album',
        { albumName: 'Gezin · Nieuwe naam' },
        userStub.admin.id,
      );
      expect(mocks.album.create).not.toHaveBeenCalled();
      expect(mocks.albumUser.create).not.toHaveBeenCalled();
      expect(mocks.albumUser.delete).not.toHaveBeenCalled();
      expect(result.familyAlbum).toEqual(expect.objectContaining({ id: 'family-album', name: 'Gezin · Nieuwe naam' }));
    });

    it('uses the oldest marked family album and reports duplicate markers', async () => {
      mocks.user.getByEmail.mockResolvedValue(userStub.admin);
      const albumUsers = [{ user: userStub.admin, role: AlbumUserRole.Owner }];
      mocks.album.getAll.mockResolvedValue([
        {
          id: 'newer-album',
          albumName: 'Gezin · Home',
          description: 'TileRun Home: home-1',
          createdAt: new Date('2026-02-01T00:00:00Z'),
        },
        {
          id: 'oldest-album',
          albumName: 'Gezin · Home',
          description: 'TileRun Home: home-1',
          createdAt: new Date('2026-01-01T00:00:00Z'),
        },
      ] as never);
      mocks.album.getById.mockResolvedValue({ id: 'oldest-album', albumName: 'Gezin · Home', albumUsers } as never);

      const result = await sut.syncTileRunUsers({
        home: { id: 'home-1', name: 'Home' },
        users: [{ email: userStub.admin.email, name: userStub.admin.name, isAdmin: true }],
        revoke: [],
      });

      expect(mocks.album.getById).toHaveBeenCalledWith('oldest-album', { withAssets: false }, userStub.admin.id);
      expect(mocks.logger.warn).toHaveBeenCalledWith(expect.stringContaining('Multiple TileRun family albums'));
      expect(mocks.album.create).not.toHaveBeenCalled();
      expect(result.familyAlbum?.id).toBe('oldest-album');
    });

    it('revokes sessions without removing an account or assets', async () => {
      mocks.user.getByEmail.mockResolvedValue(userStub.user1);
      mocks.session.getByUserId.mockResolvedValue([{ id: 'session-1' }] as never);
      mocks.session.invalidateAll.mockResolvedValue();
      mocks.event.emit.mockResolvedValue();

      const result = await sut.syncTileRunUsers({ users: [], revoke: [userStub.user1.email] });

      expect(mocks.session.invalidateAll).toHaveBeenCalledWith({ userId: userStub.user1.id });
      expect(mocks.user.delete).not.toHaveBeenCalled();
      expect(result.sessionsRevoked).toBe(1);
    });
  });

  describe('deleteSessions', () => {
    it('revokes sessions without deleting the user', async () => {
      mocks.session.getByUserId.mockResolvedValue([{ id: 'session-1' }, { id: 'session-2' }] as never);
      mocks.session.invalidateAll.mockResolvedValue();
      mocks.event.emit.mockResolvedValue();

      await expect(sut.deleteSessions(userStub.user1.id)).resolves.toBeUndefined();

      expect(mocks.session.invalidateAll).toHaveBeenCalledWith({ userId: userStub.user1.id });
      expect(mocks.event.emit).toHaveBeenCalledWith('SessionDelete', { sessionId: 'session-1' });
      expect(mocks.event.emit).toHaveBeenCalledWith('SessionDelete', { sessionId: 'session-2' });
      expect(mocks.user.delete).not.toHaveBeenCalled();
    });
  });

  describe('create', () => {
    it('should not create a user if there is no local admin account', async () => {
      mocks.user.getAdmin.mockResolvedValueOnce(void 0);

      await expect(
        sut.create({
          email: 'john_smith@email.com',
          name: 'John Smith',
          password: 'password',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('should create user', async () => {
      mocks.user.getAdmin.mockResolvedValue(userStub.admin);
      mocks.user.create.mockResolvedValue(userStub.user1);

      await expect(
        sut.create({
          email: userStub.user1.email,
          name: userStub.user1.name,
          password: 'password',
          storageLabel: 'label',
        }),
      ).resolves.toEqual(mapUserAdmin(userStub.user1));

      expect(mocks.user.getAdmin).toBeCalled();
      expect(mocks.user.create).toBeCalledWith({
        email: userStub.user1.email,
        name: userStub.user1.name,
        storageLabel: 'label',
        password: expect.anything(),
      });
    });
  });

  describe('update', () => {
    it('should update the user', async () => {
      const update = {
        shouldChangePassword: true,
        email: 'immich@test.com',
        storageLabel: 'storage_label',
      };
      mocks.user.getByEmail.mockResolvedValue(void 0);
      mocks.user.getByStorageLabel.mockResolvedValue(void 0);
      mocks.user.update.mockResolvedValue(userStub.user1);

      await sut.update(authStub.user1, userStub.user1.id, update);

      expect(mocks.user.getByEmail).toHaveBeenCalledWith(update.email);
      expect(mocks.user.getByStorageLabel).toHaveBeenCalledWith(update.storageLabel);
    });

    it('should not set an empty string for storage label', async () => {
      mocks.user.update.mockResolvedValue(userStub.user1);
      await sut.update(authStub.admin, userStub.user1.id, { storageLabel: '' });
      expect(mocks.user.update).toHaveBeenCalledWith(userStub.user1.id, {
        storageLabel: null,
        updatedAt: expect.any(Date),
      });
    });

    it('should not change an email to one already in use', async () => {
      const dto = { id: userStub.user1.id, email: 'updated@test.com' };

      mocks.user.get.mockResolvedValue(userStub.user1);
      mocks.user.getByEmail.mockResolvedValue(userStub.admin);

      await expect(sut.update(authStub.admin, userStub.user1.id, dto)).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.user.update).not.toHaveBeenCalled();
    });

    it('should not let the admin change the storage label to one already in use', async () => {
      const dto = { id: userStub.user1.id, storageLabel: 'admin' };

      mocks.user.get.mockResolvedValue(userStub.user1);
      mocks.user.getByStorageLabel.mockResolvedValue(userStub.admin);

      await expect(sut.update(authStub.admin, userStub.user1.id, dto)).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.user.update).not.toHaveBeenCalled();
    });

    it('update user information should throw error if user not found', async () => {
      mocks.user.get.mockResolvedValueOnce(void 0);

      await expect(
        sut.update(authStub.admin, userStub.user1.id, { shouldChangePassword: true }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('delete', () => {
    it('should throw error if user could not be found', async () => {
      mocks.user.get.mockResolvedValue(void 0);

      await expect(sut.delete(authStub.admin, 'not-found', {})).rejects.toThrowError(BadRequestException);
      expect(mocks.user.delete).not.toHaveBeenCalled();
    });

    it('cannot delete admin user', async () => {
      await expect(sut.delete(authStub.admin, userStub.admin.id, {})).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('should not allow deleting own account', async () => {
      const user = UserFactory.create({ isAdmin: false });
      const auth = AuthFactory.create(user);
      mocks.user.get.mockResolvedValue(user);
      await expect(sut.delete(auth, user.id, {})).rejects.toBeInstanceOf(ForbiddenException);

      expect(mocks.user.delete).not.toHaveBeenCalled();
    });

    it('should delete user', async () => {
      mocks.user.get.mockResolvedValue(userStub.user1);
      mocks.user.update.mockResolvedValue(userStub.user1);

      await expect(sut.delete(authStub.admin, userStub.user1.id, {})).resolves.toEqual(mapUserAdmin(userStub.user1));
      expect(mocks.user.update).toHaveBeenCalledWith(userStub.user1.id, {
        status: UserStatus.Deleted,
        deletedAt: expect.any(Date),
      });
    });

    it('should force delete user', async () => {
      mocks.user.get.mockResolvedValue(userStub.user1);
      mocks.user.update.mockResolvedValue(userStub.user1);

      await expect(sut.delete(authStub.admin, userStub.user1.id, { force: true })).resolves.toEqual(
        mapUserAdmin(userStub.user1),
      );

      expect(mocks.user.update).toHaveBeenCalledWith(userStub.user1.id, {
        status: UserStatus.Removing,
        deletedAt: expect.any(Date),
      });
      expect(mocks.job.queue).toHaveBeenCalledWith({
        name: JobName.UserDelete,
        data: { id: userStub.user1.id, force: true },
      });
    });
  });

  describe('restore', () => {
    it('should throw error if user could not be found', async () => {
      mocks.user.get.mockResolvedValue(void 0);
      await expect(sut.restore(authStub.admin, userStub.admin.id)).rejects.toThrowError(BadRequestException);
      expect(mocks.user.update).not.toHaveBeenCalled();
    });

    it('should restore an user', async () => {
      mocks.user.get.mockResolvedValue(userStub.user1);
      mocks.user.restore.mockResolvedValue(userStub.user1);
      await expect(sut.restore(authStub.admin, userStub.user1.id)).resolves.toEqual(mapUserAdmin(userStub.user1));
      expect(mocks.user.restore).toHaveBeenCalledWith(userStub.user1.id);
    });
  });
});
