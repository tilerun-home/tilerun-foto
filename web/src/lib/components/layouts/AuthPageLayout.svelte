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
    <div class="absolute -z-10 flex size-full place-content-center place-items-center">
      <img
        src="/tilerun-foto-logo.svg"
        class="mx-auto mb-2 h-3/4 max-w-(--breakpoint-md) overflow-hidden opacity-20 antialiased"
        alt="TileRun Foto-logo"
      />
      <div
        class="absolute inset-s-0 top-0 h-[99%] w-full bg-transparent backdrop-blur-[200px] dark:bg-immich-dark-bg/20"
      ></div>
    </div>
  {/if}

  <Card color="secondary" class="m-2 w-full max-w-xl border">
    {#if withHeader}
      <CardHeader class="mt-6">
        <VStack>
          <TileRunFotoLogo variant="inline" size="giant" />
          <Heading size="large" class="font-semibold" color="primary" tag="h1">{title}</Heading>
        </VStack>
      </CardHeader>
    {/if}

    <CardBody class="p-8">
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
