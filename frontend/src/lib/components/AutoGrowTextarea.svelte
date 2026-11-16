<script lang="ts">
  import { onMount, tick } from "svelte";

  /**
   * A textarea that grows with its text.
   *
   * Starts at `rows` lines, grows as the user types, and scrolls once it
   * reaches `maxHeight`. Used for the comment fields on the worklists, where a
   * fixed two-line box made longer comments hard to read back before saving.
   *
   * Done in script rather than with CSS `field-sizing: content`, which
   * Firefox does not support.
   */

  // No default value on purpose: the worklists bind a per-bevilling entry that
  // is undefined until someone types, and Svelte 5 refuses to bind undefined
  // to a prop that has a fallback.
  export let value: string | undefined;
  export let rows = 3;
  export let placeholder = "";
  /** Any CSS length. Past this the field scrolls instead of growing. */
  export let maxHeight = "16rem";

  let className = "";
  export { className as class };

  let el: HTMLTextAreaElement;

  async function tilpasHoejde() {
    // Wait for the DOM to hold the new value; when the parent clears the
    // field after saving, the value arrives before the textarea shows it.
    await tick();

    if (!el) return;

    // Reset first, or the field could only ever grow: scrollHeight never
    // reports less than the current height.
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  }

  // Also covers changes from outside, such as the field being cleared after save.
  $: value, tilpasHoejde();

  onMount(tilpasHoejde);
</script>

<textarea
  bind:this={el}
  bind:value
  {rows}
  {placeholder}
  style="max-height: {maxHeight}; overflow-y: auto;"
  class="resize-none {className}"
></textarea>
