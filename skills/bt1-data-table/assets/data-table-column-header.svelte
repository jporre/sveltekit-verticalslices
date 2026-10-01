<script lang="ts" module>
/**
 * i18n — translate these four strings to match your project's language.
 * They are the ONLY user-facing copy baked into this component; everything
 * else (column titles, placeholders) is passed in per-column.
 */
const STRINGS = {
  filterPlaceholder: 'Filter…',
  noResults: 'No results.',
  clearFilters: 'Clear filters',
  rangeSeparator: 'to',
}
</script>

<script lang="ts" generics="TData extends RowData, TValue">
import ArrowDown from '@lucide/svelte/icons/arrow-down'
import ArrowUp from '@lucide/svelte/icons/arrow-up'
import ChevronsUpDown from '@lucide/svelte/icons/chevrons-up-down'
import Filter from '@lucide/svelte/icons/filter'
import X from '@lucide/svelte/icons/x'
import CheckIcon from '@lucide/svelte/icons/check'
import CirclePlusIcon from '@lucide/svelte/icons/circle-plus'
import type {HTMLAttributes} from 'svelte/elements'
import type {Column, RowData, TableFeatures} from '@tanstack/svelte-table'
import type {WithoutChildren} from 'bits-ui'
import type {Component} from 'svelte'
import {cn} from '$lib/utils.js'
import Button from '$lib/components/ui/button/button.svelte'
import Input from '$lib/components/ui/input/input.svelte'
import {Badge} from '$lib/components/ui/badge/index.js'
import * as Command from '$lib/components/ui/command/index.js'
import * as Popover from '$lib/components/ui/popover/index.js'
import {Separator} from '$lib/components/ui/separator/index.js'
import {SvelteSet} from 'svelte/reactivity'

type Props = HTMLAttributes<HTMLDivElement> & {
  // Column<TableFeatures, …>: el tipo all-features expone los métodos gated de
  // filtrado/orden; con un TFeatures genérico la unión de combinaciones no
  // resuelve. Los callers con features concretos hacen cast `as any`.
  column: Column<TableFeatures, TData, TValue>
  title: string
  enableFilter?: boolean
  filterPlaceholder?: string
  filterType?: 'text' | 'date' | 'dateRange'
  /**
   * `filterOptions` turns the header into a faceted multi-select:
   *   - an explicit list of `{label, value, icon?}` — for fixed enums/booleans
   *   - `'auto'` — values are discovered from the data via `getFacetedUniqueValues()`
   * Pair it with an array `filterFn` (see column-recipes.md).
   */
  filterOptions?:
    | {
        label: string
        value: string | boolean
        icon?: Component
      }[]
    | 'auto'
}

let {column, class: className, title, enableFilter = false, filterPlaceholder = STRINGS.filterPlaceholder, filterType = 'text', filterOptions = undefined, ...restProps}: WithoutChildren<Props> = $props()

let showFilter = $state(false)
let filterValue = $state('')

// Date filter state
let dateFromValue = $state('')
let dateToValue = $state('')

// Faceted (option) filter state
const isOptionFilter = $derived(!!filterOptions)
const isDateFilter = $derived(filterType === 'date' || filterType === 'dateRange')
const facets = $derived(column?.getFacetedUniqueValues())
const selectedValues = $derived(new SvelteSet(column?.getFilterValue() as (string | boolean)[]))

// When `filterOptions === 'auto'`, build the option list from the faceted unique values.
const resolvedFilterOptions = $derived.by(() => {
  if (filterOptions === 'auto') {
    const uniqueValues = facets ?? new Map()
    return Array.from(uniqueValues.entries()).map(([value, count]) => ({
      value,
      label: String(value),
      icon: undefined as Component | undefined,
      count,
    }))
  }
  return filterOptions ?? []
})

// Keep the local text input in sync with the column's filter state.
$effect(() => {
  if (!isOptionFilter) {
    filterValue = (column.getFilterValue() as string) ?? ''
  }
})

function handleFilterChange(value: string) {
  filterValue = value
  column.setFilterValue(value || undefined)
}

function clearFilter() {
  filterValue = ''
  column.setFilterValue(undefined)
}

function toggleFilter() {
  showFilter = !showFilter
}

function handleOptionSelect(optionValue: string | boolean) {
  if (selectedValues.has(optionValue)) {
    selectedValues.delete(optionValue)
  } else {
    selectedValues.add(optionValue)
  }
  const filterValues = Array.from(selectedValues)
  column?.setFilterValue(filterValues.length ? filterValues : undefined)
}

function clearOptionFilter() {
  column?.setFilterValue(undefined)
}

function handleDateChange(value: string) {
  filterValue = value
  if (filterType === 'date') {
    column.setFilterValue(value || undefined)
  }
}

function handleDateRangeChange() {
  if (filterType === 'dateRange') {
    const from = dateFromValue
    const to = dateToValue
    if (from || to) {
      column.setFilterValue({from, to})
    } else {
      column.setFilterValue(undefined)
    }
  }
}

function clearDateFilter() {
  if (filterType === 'date') {
    filterValue = ''
    column.setFilterValue(undefined)
  } else if (filterType === 'dateRange') {
    dateFromValue = ''
    dateToValue = ''
    column.setFilterValue(undefined)
  }
}
</script>

{#if !column?.getCanSort()}
  <div class={cn('flex items-center gap-1', className)} {...restProps}>
    {title}
    {#if enableFilter}
      {#if isOptionFilter}
        <!-- Faceted multi-select filter -->
        <Popover.Root>
          <Popover.Trigger>
            {#snippet child({props})}
              <Button {...props} variant="ghost" size="sm" class="h-6 w-6 p-0">
                <CirclePlusIcon class="h-3 w-3" />
                {#if selectedValues.size > 0}
                  <Badge variant="secondary" class="ml-1 rounded-sm px-1 text-xs font-normal">
                    {selectedValues.size}
                  </Badge>
                {/if}
              </Button>
            {/snippet}
          </Popover.Trigger>
          <Popover.Content class="w-[200px] p-0" align="start">
            <Command.Root>
              <Command.Input placeholder={title} />
              <Command.List>
                <Command.Empty>{STRINGS.noResults}</Command.Empty>
                <Command.Group>
                  {#each resolvedFilterOptions as option (option)}
                    {@const isSelected = selectedValues.has(option.value)}
                    <Command.Item onSelect={() => handleOptionSelect(option.value)}>
                      <div class={cn('border-primary mr-2 flex size-4 items-center justify-center rounded-sm border', isSelected ? 'bg-primary text-primary-foreground' : 'opacity-50 [&_svg]:invisible')}>
                        <CheckIcon class="size-4" />
                      </div>
                      {#if option.icon}
                        {@const Icon = option.icon}
                        <Icon class="text-muted-foreground mr-2" />
                      {/if}
                      <span>{option.label}</span>
                      {#if facets?.get(option.value)}
                        <span class="ml-auto flex size-4 items-center justify-center font-mono text-xs">
                          {facets.get(option.value)}
                        </span>
                      {/if}
                    </Command.Item>
                  {/each}
                </Command.Group>
                {#if selectedValues.size > 0}
                  <Command.Separator />
                  <Command.Group>
                    <Command.Item onSelect={clearOptionFilter} class="justify-center text-center">{STRINGS.clearFilters}</Command.Item>
                  </Command.Group>
                {/if}
              </Command.List>
            </Command.Root>
          </Popover.Content>
        </Popover.Root>
      {:else}
        <!-- Free-text / date filter -->
        <Button variant="ghost" size="sm" class="h-6 w-6 p-0" onclick={toggleFilter}>
          <Filter class="h-3 w-3" />
        </Button>
        {#if showFilter}
          <div class="ml-2 flex items-center gap-1">
            {#if isDateFilter}
              {#if filterType === 'date'}
                <Input type="date" placeholder={filterPlaceholder} value={filterValue} oninput={e => handleDateChange(e.currentTarget.value)} class="h-6 w-36 text-xs" />
                {#if filterValue}
                  <Button variant="ghost" size="sm" class="h-6 w-6 p-0" onclick={clearDateFilter}>
                    <X class="h-3 w-3" />
                  </Button>
                {/if}
              {:else if filterType === 'dateRange'}
                <div class="flex items-center gap-1">
                  <Input
                    type="date"
                    value={dateFromValue}
                    oninput={e => {
                      dateFromValue = e.currentTarget.value
                      handleDateRangeChange()
                    }}
                    class="h-6 w-32 text-xs"
                  />
                  <span class="text-xs">{STRINGS.rangeSeparator}</span>
                  <Input
                    type="date"
                    value={dateToValue}
                    oninput={e => {
                      dateToValue = e.currentTarget.value
                      handleDateRangeChange()
                    }}
                    class="h-6 w-32 text-xs"
                  />
                  {#if dateFromValue || dateToValue}
                    <Button variant="ghost" size="sm" class="h-6 w-6 p-0" onclick={clearDateFilter}>
                      <X class="h-3 w-3" />
                    </Button>
                  {/if}
                </div>
              {/if}
            {:else}
              <Input placeholder={filterPlaceholder} value={filterValue} oninput={e => handleFilterChange(e.currentTarget.value)} class="h-6 w-32 text-xs" />
              {#if filterValue}
                <Button variant="ghost" size="sm" class="h-6 w-6 p-0" onclick={clearFilter}>
                  <X class="h-3 w-3" />
                </Button>
              {/if}
            {/if}
          </div>
        {/if}
      {/if}
    {/if}
  </div>
{:else}
  <div class={cn('flex flex-col gap-1', className)} {...restProps}>
    <div class="flex items-center">
      <Button variant="ghost" size="sm" class={cn('data-[state=open]:bg-accent -ml-3 h-8', className)} onclick={() => column.toggleSorting()}>
        <h3 class="text-[10.5px] font-semibold uppercase tracking-wide leading-none">
          {title}
        </h3>
        {#if column.getIsSorted() === 'desc'}
          <ArrowDown />
        {:else if column.getIsSorted() === 'asc'}
          <ArrowUp />
        {:else}
          <ChevronsUpDown />
        {/if}
      </Button>
      {#if enableFilter}
        {#if isOptionFilter}
          <!-- Faceted multi-select filter (sortable column) -->
          <Popover.Root>
            <Popover.Trigger>
              {#snippet child({props})}
                <Button {...props} variant="ghost" size="sm" class="ml-1 h-6 w-6 p-0">
                  <CirclePlusIcon class="h-3 w-3" />
                  {#if selectedValues.size > 0}
                    <Badge variant="secondary" class="ml-1 rounded-sm px-1 text-xs font-normal">
                      {selectedValues.size}
                    </Badge>
                  {/if}
                </Button>
              {/snippet}
            </Popover.Trigger>
            <Popover.Content class="w-[200px] p-0" align="start">
              <Command.Root>
                <Command.Input placeholder={title} />
                <Command.List>
                  <Command.Empty>{STRINGS.noResults}</Command.Empty>
                  <Command.Group>
                    {#each resolvedFilterOptions as option (option)}
                      {@const isSelected = selectedValues.has(option.value)}
                      <Command.Item onSelect={() => handleOptionSelect(option.value)}>
                        <div class={cn('border-primary mr-2 flex size-4 items-center justify-center rounded-sm border', isSelected ? 'bg-primary text-primary-foreground' : 'opacity-50 [&_svg]:invisible')}>
                          <CheckIcon class="size-4" />
                        </div>
                        {#if option.icon}
                          {@const Icon = option.icon}
                          <Icon class="text-muted-foreground mr-2" />
                        {/if}
                        <span>{option.label}</span>
                        {#if facets?.get(option.value)}
                          <span class="ml-auto flex size-4 items-center justify-center font-mono text-xs">
                            {facets.get(option.value)}
                          </span>
                        {/if}
                      </Command.Item>
                    {/each}
                  </Command.Group>
                  {#if selectedValues.size > 0}
                    <Command.Separator />
                    <Command.Group>
                      <Command.Item onSelect={clearOptionFilter} class="justify-center text-center">{STRINGS.clearFilters}</Command.Item>
                    </Command.Group>
                  {/if}
                </Command.List>
              </Command.Root>
            </Popover.Content>
          </Popover.Root>
        {:else}
          <!-- Free-text / date filter toggle (sortable column) -->
          <Button variant="ghost" size="sm" class="ml-1 h-6 w-6 p-0" onclick={toggleFilter}>
            <Filter class="h-3 w-3" />
          </Button>
        {/if}
      {/if}
    </div>
    {#if enableFilter && showFilter && !isOptionFilter}
      <div class="flex items-center gap-1 px-3">
        {#if isDateFilter}
          {#if filterType === 'date'}
            <Input type="date" placeholder={filterPlaceholder} value={filterValue} oninput={e => handleDateChange(e.currentTarget.value)} class="h-7 w-40 text-xs" />
            {#if filterValue}
              <Button variant="ghost" size="sm" class="h-6 w-6 p-0" onclick={clearDateFilter}>
                <X class="h-3 w-3" />
              </Button>
            {/if}
          {:else if filterType === 'dateRange'}
            <div class="flex items-center gap-1">
              <Input
                type="date"
                value={dateFromValue}
                oninput={e => {
                  dateFromValue = e.currentTarget.value
                  handleDateRangeChange()
                }}
                class="h-7 w-36 text-xs"
              />
              <span class="text-xs">{STRINGS.rangeSeparator}</span>
              <Input
                type="date"
                value={dateToValue}
                oninput={e => {
                  dateToValue = e.currentTarget.value
                  handleDateRangeChange()
                }}
                class="h-7 w-36 text-xs"
              />
              {#if dateFromValue || dateToValue}
                <Button variant="ghost" size="sm" class="h-6 w-6 p-0" onclick={clearDateFilter}>
                  <X class="h-3 w-3" />
                </Button>
              {/if}
            </div>
          {/if}
        {:else}
          <Input placeholder={filterPlaceholder} value={filterValue} oninput={e => handleFilterChange(e.currentTarget.value)} class="h-7 text-xs" />
          {#if filterValue}
            <Button variant="ghost" size="sm" class="h-6 w-6 p-0" onclick={clearFilter}>
              <X class="h-3 w-3" />
            </Button>
          {/if}
        {/if}
      </div>
    {/if}
  </div>
{/if}
