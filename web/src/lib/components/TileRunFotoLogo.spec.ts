import { render, screen } from '@testing-library/svelte';
import TileRunFotoLogo from './TileRunFotoLogo.svelte';

describe('TileRunFotoLogo', () => {
  it('keeps the public branding generic by default', () => {
    render(TileRunFotoLogo, { variant: 'inline' });

    expect(screen.getByText('TileRun')).toBeInTheDocument();
    expect(screen.getByText('FOTO')).toBeInTheDocument();
  });

  it('shows the configured Home name with accessible full text', () => {
    const homeName = 'Een bijzonder lange centrale Home-naam die visueel wordt afgekapt';
    render(TileRunFotoLogo, {
      variant: 'inline',
      primaryLabel: homeName,
      secondaryLabel: 'TileRun FOTO',
    });

    expect(screen.getByTitle(homeName)).toHaveAttribute('aria-label', `${homeName} · TileRun FOTO`);
    expect(screen.getByText(homeName)).toHaveClass('truncate');
    expect(screen.getByText('TileRun FOTO')).toBeInTheDocument();
  });
});
