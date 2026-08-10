<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { tileRunProfileManager } from '$lib/managers/tilerun-profile-manager.svelte';
  import { lang } from '$lib/stores/preferences.store';
  import { handleError } from '$lib/utils/handle-error';
  import { convertBCP47, langs } from '$lib/utils/i18n';
  import type { TileRunProfile } from '$lib/utils/tilerun-profile';
  import { Button, Field, Input, toastManager } from '@immich/ui';
  import { onMount } from 'svelte';
  import { locale as i18nLocale, t } from 'svelte-i18n';
  import { createBubbler, preventDefault } from 'svelte/legacy';
  import { fade } from 'svelte/transition';

  let profile = $state<TileRunProfile>();
  let displayName = $state('');
  let preferredLanguage = $state('');
  let saving = $state(false);
  const bubble = createBubbler();

  const loadProfile = async () => {
    profile = await tileRunProfileManager.load(authManager.user.email);
    if (!profile) {
      throw new Error('TileRun-profiel kon niet worden geladen');
    }
    displayName = profile.display_name;
    preferredLanguage = profile.preferred_language || '';
  };

  onMount(() => loadProfile().catch((error) => handleError(error, 'TileRun-profiel kon niet worden geladen')));

  const save = async () => {
    if (!profile) return;
    saving = true;
    try {
      profile = await tileRunProfileManager.update({
        displayName,
        preferredLanguage: preferredLanguage || null,
        version: profile.version,
      });
      displayName = profile.display_name;
      preferredLanguage = profile.preferred_language || '';
      $lang = profile.effective_language;
      await i18nLocale.set(convertBCP47(profile.effective_language));
      await authManager.refresh();
      await invalidateAll();
      toastManager.primary($t('saved_profile'));
    } catch (error) {
      handleError(error, $t('errors.unable_to_save_profile'));
    } finally {
      saving = false;
    }
  };
</script>

<section class="my-4">
  <div in:fade={{ duration: 300 }}>
    <form autocomplete="off" onsubmit={preventDefault(bubble('submit'))}>
      <div class="flex flex-col gap-4 sm:ms-8">
        <Field label={$t('email')} description="Je e-mailadres wordt centraal door TileRun beheerd." disabled>
          <Input type="email" value={profile?.email || authManager.user.email} disabled />
        </Field>

        <Field label={$t('name')} description="Deze naam wordt in alle TileRun-onderdelen gebruikt." required>
          <Input bind:value={displayName} minlength={2} maxlength={100} disabled={!profile} />
        </Field>

        <Field
          label={$t('language')}
          description={profile ? `Standaard van ${profile.home_name}: ${profile.home_default_language}` : ''}
        >
          <select
            class="w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-sm dark:border-gray-600 dark:bg-immich-dark-gray"
            bind:value={preferredLanguage}
            disabled={!profile}
          >
            <option value="">Gebruik taal van {profile?.home_name || 'TileRun Home'}</option>
            {#each langs as language (language.code)}
              <option value={convertBCP47(language.code)}>{language.name}</option>
            {/each}
          </select>
        </Field>

        <p class="text-sm text-gray-500">
          Je profielfoto wijzig je via de ronde profielknop rechtsboven. Ook die wordt centraal in TileRun opgeslagen.
        </p>

        <div class="flex justify-end">
          <Button shape="round" type="submit" size="small" disabled={!profile || saving} onclick={save}>
            {$t('save')}
          </Button>
        </div>
      </div>
    </form>
  </div>
</section>
