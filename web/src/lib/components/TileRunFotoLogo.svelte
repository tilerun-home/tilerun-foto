<script lang="ts">
  interface Props {
    variant?: 'icon' | 'inline';
    size?: 'tiny' | 'small' | 'medium' | 'large' | 'giant';
    class?: string;
  }

  let { variant = 'icon', size = 'medium', class: className = '' }: Props = $props();

  const heights = {
    tiny: 24,
    small: 32,
    medium: 40,
    large: 56,
    giant: 88,
  } as const;

  const height = $derived(heights[size]);
  const width = $derived(variant === 'inline' ? Math.round(height * 3.45) : height);
</script>

<svg
  {width}
  {height}
  viewBox={variant === 'inline' ? '0 0 224 64' : '0 0 64 64'}
  role="img"
  aria-label="TileRun Foto"
  class={className}
  xmlns="http://www.w3.org/2000/svg"
>
  <rect width="64" height="64" rx="18" fill="#477e60" />
  <path d="M16 29 32 16l16 13v19H37V36H27v12H16Z" fill="#fdf6e3" />
  <path d="M23 25h18" stroke="#ac9d57" stroke-width="4" stroke-linecap="round" />
  <rect x="35" y="36" width="17" height="13" rx="4" fill="#315b45" stroke="#fdf6e3" stroke-width="2" />
  <circle cx="43.5" cy="42.5" r="3.2" fill="#fdf6e3" />
  <path d="M39 36.5 41 34h5l2 2.5" fill="#315b45" stroke="#fdf6e3" stroke-width="2" stroke-linejoin="round" />
  {#if variant === 'inline'}
    <text x="78" y="31" fill="currentColor" font-size="23" font-weight="850" font-family="Inter, ui-sans-serif, system-ui, sans-serif">TileRun</text>
    <text x="78" y="51" fill="#477e60" font-size="17" font-weight="750" font-family="Inter, ui-sans-serif, system-ui, sans-serif">Foto</text>
  {/if}
</svg>

