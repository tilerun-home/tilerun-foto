<script lang="ts">
  import TileRunFotoLogo from '$lib/components/TileRunFotoLogo.svelte';
  import TileRunFotoLinks from '$lib/components/TileRunFotoLinks.svelte';
  import { Card, CardBody, CardHeader, Heading, VStack } from '@immich/ui';
  import type { Snippet } from 'svelte';
  interface Props {
    title?: string;
    children?: Snippet;
    withHeader?: boolean;
    withBackdrop?: boolean;
  }

  let { title, children, withHeader = true, withBackdrop = true }: Props = $props();
</script>

<section class="relative isolate flex min-h-dvh min-w-dvw items-center justify-center">
  {#if withBackdrop}
    <div class="tilerun-auth-backdrop absolute inset-0 -z-10"></div>
  {/if}

  <Card color="secondary" class="tilerun-auth-card m-4 w-full max-w-lg border">
    {#if withHeader}
      <CardHeader class="mt-5">
        <VStack>
          <TileRunFotoLogo variant="inline" size="large" />
          <Heading size="large" class="mt-2 font-bold tracking-[-0.025em]" color="primary" tag="h1">{title}</Heading>
        </VStack>
      </CardHeader>
    {/if}

    <CardBody class="px-8 pt-6 pb-7">
      {@render children?.()}
      <div class="mt-8 border-t border-gray-200 pt-5 dark:border-gray-700">
        <TileRunFotoLinks />
        <p class="mt-3 text-center text-xs text-gray-500 dark:text-gray-400">
          Gebouwd op Immich · AGPLv3 · je foto's blijven op je TileRun Home
        </p>
      </div>
    </CardBody>
  </Card>
</section>
