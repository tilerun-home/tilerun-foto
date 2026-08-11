import { TileRunProfileManager } from '$lib/managers/tilerun-profile-manager.svelte';
import { getTileRunProfile } from '$lib/utils/tilerun-profile';

vi.mock('$lib/utils/tilerun-profile', () => ({
  getTileRunProfile: vi.fn(),
  updateTileRunProfile: vi.fn(),
}));

describe(TileRunProfileManager.name, () => {
  beforeEach(() => vi.clearAllMocks());

  it('loads a profile only once for an authenticated email', async () => {
    vi.mocked(getTileRunProfile).mockResolvedValue({ home_name: 'Bolsius - Pedraza' } as never);
    const manager = new TileRunProfileManager();

    await manager.load('user@example.com');
    await manager.load('USER@example.com');

    expect(getTileRunProfile).toHaveBeenCalledTimes(1);
    expect(manager.profile?.home_name).toBe('Bolsius - Pedraza');
  });

  it('does not create a request loop after a failed profile request', async () => {
    vi.mocked(getTileRunProfile).mockRejectedValue(new Error('offline'));
    const manager = new TileRunProfileManager();

    await manager.load('user@example.com');
    await manager.load('user@example.com');

    expect(getTileRunProfile).toHaveBeenCalledTimes(1);
    expect(manager.profile).toBeUndefined();
  });

  it('retries only after an explicit refresh', async () => {
    vi.mocked(getTileRunProfile)
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce({ home_name: 'Bolsius - Pedraza' } as never);
    const manager = new TileRunProfileManager();

    await manager.load('user@example.com');
    await manager.refresh();

    expect(getTileRunProfile).toHaveBeenCalledTimes(2);
    expect(manager.profile?.home_name).toBe('Bolsius - Pedraza');
  });
});
