import { Body, Controller, Get, Headers, Patch, Post, UnauthorizedException } from '@nestjs/common';
import { AuthDto } from 'src/dtos/auth.dto';
import { TileRunProfileUpdateDto, TileRunUserSyncDto } from 'src/dtos/tilerun-profile.dto';
import { Permission } from 'src/enum';
import { Auth, Authenticated } from 'src/middleware/auth.guard';
import { UserAdminService } from 'src/services/user-admin.service';
import { UserService } from 'src/services/user.service';
import { validateTileRunServiceToken } from 'src/utils/tilerun-profile';

@Controller('tilerun/profile')
export class TileRunProfileController {
  constructor(
    private service: UserService,
    private userAdminService: UserAdminService,
  ) {}

  @Post('users/sync')
  syncUsers(@Headers('x-tilerun-service-token') token: string | undefined, @Body() dto: TileRunUserSyncDto) {
    if (!validateTileRunServiceToken(token)) {
      throw new UnauthorizedException();
    }
    return this.userAdminService.syncTileRunUsers(dto);
  }

  @Get()
  @Authenticated({ permission: Permission.UserRead })
  getProfile(@Auth() auth: AuthDto) {
    return this.service.getCentralProfile(auth);
  }

  @Patch()
  @Authenticated({ permission: Permission.UserUpdate })
  updateProfile(@Auth() auth: AuthDto, @Body() dto: TileRunProfileUpdateDto) {
    return this.service.updateCentralProfile(auth, dto);
  }
}
