<script lang="ts">
  import ButtonContextMenu from '$lib/components/shared-components/context-menu/ButtonContextMenu.svelte';
  import MenuOption from '$lib/components/shared-components/context-menu/MenuOption.svelte';
  import { mdiDotsVertical, mdiGithub, mdiHeartPulse, mdiLifebuoy } from '@mdi/js';

  const open = (url: string, target: '_self' | '_blank' = '_self') => {
    if (target === '_blank') {
      window.open(url, '_blank', 'noopener,noreferrer');
      return;
    }
    window.location.assign(url);
  };
</script>

<ButtonContextMenu
  icon={mdiDotsVertical}
  title="Meer TileRun-links"
  align="top-right"
  direction="left"
  size="medium"
  hideContent
>
  <MenuOption
    icon={mdiHeartPulse}
    text="Status"
    subtitle="Systeemstatus bekijken"
    onClick={() => open('https://tilerun.net/health')}
  />
  <MenuOption icon={mdiLifebuoy} text="Support" onClick={() => open('https://tilerun.net')} />
  <MenuOption
    icon={mdiGithub}
    text="Broncode"
    subtitle="Opent in een nieuw tabblad"
    onClick={() => open('https://github.com/tilerun-home/tilerun-foto', '_blank')}
  />
</ButtonContextMenu>
