import { createZodDto } from 'nestjs-zod';
import z from 'zod';

const TileRunProfileUpdateSchema = z.object({
  displayName: z.string().trim().min(2).max(100).optional(),
  preferredLanguage: z
    .string()
    .trim()
    .regex(/^[a-z]{2,3}(?:-[A-Z]{2})?$/)
    .nullable()
    .optional(),
  version: z.number().int().positive().optional(),
});

export class TileRunProfileUpdateDto extends createZodDto(TileRunProfileUpdateSchema) {}

const TileRunProvisionedUserSchema = z.object({
  email: z.email(),
  name: z.string().trim().min(1).max(200),
  isAdmin: z.boolean().optional().default(false),
});

const TileRunHomeSchema = z.object({
  id: z.string().trim().min(1).max(100),
  name: z.string().trim().min(2).max(100),
});

export const TileRunUserSyncSchema = z.object({
  home: TileRunHomeSchema.default({ id: 'primary', name: 'TileRun Home' }),
  users: z.array(TileRunProvisionedUserSchema).max(1000),
  revoke: z.array(z.email()).max(1000).default([]),
});

export class TileRunUserSyncDto extends createZodDto(TileRunUserSyncSchema) {}
