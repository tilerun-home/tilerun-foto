<script lang="ts">
  interface Props {
    variant?: 'icon' | 'inline';
    size?: 'tiny' | 'small' | 'medium' | 'large' | 'giant';
    class?: string;
  }

  let { variant = 'icon', size = 'medium', class: className = '' }: Props = $props();

  const heights = {
    tiny: 22,
    small: 30,
    medium: 36,
    large: 46,
    giant: 56,
  } as const;

  const height = $derived(heights[size]);
  const wordmarkSize = $derived(Math.max(15, Math.round(height * 0.46)));
</script>

<span
  class="inline-flex shrink-0 items-center gap-2.5 text-dark dark:text-light {className}"
  style="height: {height}px"
>
  <img src="/tilerun-foto-logo-v2.svg" alt="" width={height} {height} class="block rounded-[22%]" />
  {#if variant === 'inline'}
    <span class="flex min-w-0 flex-col leading-none" style="font-size: {wordmarkSize}px">
      <strong class="font-extrabold tracking-[-0.025em]">TileRun</strong>
      <span class="mt-1 text-[0.72em] font-bold tracking-[0.08em] text-primary uppercase">Foto</span>
    </span>
  {/if}
</span>
