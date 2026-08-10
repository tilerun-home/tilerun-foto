<script lang="ts">
  import SettingAccordion from '$lib/components/shared-components/settings/SettingAccordion.svelte';
  import { OpenQueryParam } from '$lib/constants';
  import type { ApiKeyResponseDto, SessionResponseDto } from '@immich/sdk';
  import { mdiAccountGroupOutline, mdiAccountOutline, mdiBellOutline, mdiCogOutline, mdiDevices } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import AppSettings from './AppSettings.svelte';
  import DeviceList from './DeviceList.svelte';
  import DownloadSettings from './DownloadSettings.svelte';
  import FeatureSettings from './FeatureSettings.svelte';
  import NotificationsSettings from './NotificationsSettings.svelte';
  import PartnerSettings from './PartnerSettings.svelte';
  import ChangePinCodeSettings from './PinCodeSettings.svelte';
  import UserProfileSettings from './UserProfileSettings.svelte';

  interface Props {
    keys?: ApiKeyResponseDto[];
    sessions?: SessionResponseDto[];
  }

  let { keys: _keys = [], sessions = $bindable([]) }: Props = $props();
</script>

<SettingAccordion
  icon={mdiAccountOutline}
  key="account"
  title="Profiel en taal"
  subtitle="Beheer je centrale TileRun-profiel"
>
  <UserProfileSettings />
</SettingAccordion>

<SettingAccordion icon={mdiCogOutline} key="preferences" title="Voorkeuren" subtitle="Weergave, functies en downloads">
  <AppSettings />
  <div class="my-8 border-t border-gray-200 dark:border-gray-700"></div>
  <FeatureSettings />
  <div class="my-8 border-t border-gray-200 dark:border-gray-700"></div>
  <DownloadSettings />
</SettingAccordion>

<SettingAccordion
  icon={mdiBellOutline}
  key={OpenQueryParam.NOTIFICATIONS}
  title={$t('notifications')}
  subtitle={$t('notifications_setting_description')}
>
  <NotificationsSettings />
</SettingAccordion>

<SettingAccordion
  icon={mdiDevices}
  key="privacy-devices"
  title="Privacy en apparaten"
  subtitle="Beheer sessies, apparaten en je pincode"
>
  <DeviceList bind:devices={sessions} />
  <div class="my-8 border-t border-gray-200 dark:border-gray-700"></div>
  <ChangePinCodeSettings />
</SettingAccordion>

<SettingAccordion
  icon={mdiAccountGroupOutline}
  key="partner-sharing"
  title={$t('partner_sharing')}
  subtitle={$t('manage_sharing_with_partners')}
>
  <PartnerSettings />
</SettingAccordion>
