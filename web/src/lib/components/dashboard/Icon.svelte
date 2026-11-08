<script lang="ts">
  export type IconName = 'page' | 'people' | 'lock' | 'unlock' | 'trash' | 'plus' | 'search' | 'chevron' | 'chevron-right' | 'chevron-left' | 'menu' | 'close' | 'restore' | 'pin' | 'grid' | 'list' | 'gear' | 'sort' | 'upload' | 'share' | 'download' | 'panel' | 'copy' | 'zen'

  interface Props {
    name: IconName
    size?: number
  }

  let { name, size = 18 }: Props = $props()
</script>

<svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="shrink-0">
  {#if name === 'page'}
    <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><path d="M14 3v5h5" />
  {:else if name === 'people'}
    <circle cx="12" cy="8" r="3.5" /><path d="M5 20c0-3.5 3-6 7-6s7 2.5 7 6" />
  {:else if name === 'lock'}
    <rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" />
  {:else if name === 'unlock'}
    <rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 0 1 7.5-2" />
  {:else if name === 'trash'}
    <path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3" />
  {:else if name === 'plus'}
    <path d="M12 5v14M5 12h14" />
  {:else if name === 'search'}
    <circle cx="11" cy="11" r="6.5" /><path d="m16 16 4 4" />
  {:else if name === 'chevron'}
    <path d="m6 9 6 6 6-6" />
  {:else if name === 'chevron-right'}
    <path d="m9 6 6 6-6 6" />
  {:else if name === 'chevron-left'}
    <path d="m15 6-6 6 6 6" />
  {:else if name === 'menu'}
    <path d="M4 7h16M4 12h16M4 17h16" />
  {:else if name === 'close'}
    <path d="M6 6l12 12M18 6 6 18" />
  {:else if name === 'restore'}
    <path d="M4 12a8 8 0 1 0 3-6.2M4 4v4h4" />
  {:else if name === 'pin'}
    <path d="M9 4h6l-1 6 3 3H7l3-3zM12 13v7" />
  {:else if name === 'grid'}
    <rect x="4" y="4" width="7" height="7" rx="1.5" /><rect x="13" y="4" width="7" height="7" rx="1.5" /><rect x="4" y="13" width="7" height="7" rx="1.5" /><rect x="13" y="13" width="7" height="7" rx="1.5" />
  {:else if name === 'list'}
    <path d="M4 7h16M4 12h16M4 17h16" />
  {:else if name === 'gear'}
    <circle cx="12" cy="12" r="3.2" /><path d="M12 2.8v2.6M12 18.6v2.6M4.6 7.4l2.2 1.3M17.2 15.3l2.2 1.3M4.6 16.6l2.2-1.3M17.2 8.7l2.2-1.3" />
  {:else if name === 'sort'}
    <path d="M7 4v16M7 20l-3-3M17 20V4M17 4l3 3" />
  {:else if name === 'upload'}
    <path d="M12 16V5M7.5 9.5 12 5l4.5 4.5M5 19h14" />
  {:else if name === 'share'}
    <circle cx="18" cy="5.5" r="2.5" /><circle cx="6" cy="12" r="2.5" /><circle cx="18" cy="18.5" r="2.5" /><path d="m8.2 10.8 7.6-4M8.2 13.2l7.6 4" />
  {:else if name === 'download'}
    <path d="M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19h14" />
  {:else if name === 'panel'}
    <rect x="3.5" y="4.5" width="17" height="15" rx="2" /><path d="M14.5 4.5v15" />
  {:else if name === 'copy'}
    <rect x="8.5" y="8.5" width="11" height="11" rx="2" /><path d="M15.5 8.5v-2a2 2 0 0 0-2-2h-7a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h2" />
  {:else if name === 'zen'}
    <path d="M4 9V5a1 1 0 0 1 1-1h4M15 4h4a1 1 0 0 1 1 1v4M20 15v4a1 1 0 0 1-1 1h-4M9 20H5a1 1 0 0 1-1-1v-4" />
  {/if}
</svg>
