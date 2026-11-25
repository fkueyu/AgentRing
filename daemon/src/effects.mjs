// Effect and palette catalogues: one source of truth for allowed IDs, labels,
// swatches and defaults.
//
// Motion and colour are independent axes, and the idle ring and running
// sessions share the same colour vocabulary: a palette is either an identity
// palette (state / source) or a curated ramp of stops. A palette is a *value*,
// not a macro: picking one never rewrites another setting.

export const EFFECT_CATALOG = Object.freeze({
  thinking: {
    default: 'breathe',
    options: [
      { id: 'breathe', label: '呼吸', hint: '亮度缓慢起伏' },
      { id: 'comet', label: '巡游', hint: '一个光点沿整段扫过' },
    ],
  },
  tool: {
    default: 'comet',
    options: [
      { id: 'breathe', label: '呼吸', hint: '明暗缓慢呼吸' },
      { id: 'comet', label: '巡游', hint: '光点快速扫过整段' },
      { id: 'pulse', label: '脉冲', hint: '整段亮度有节奏地脉冲' },
    ],
  },
  editing: {
    default: 'patches',
    options: [
      { id: 'patches', label: '雨滴', hint: '雨滴随机出现，拖着短尾漂移' },
      { id: 'pulse', label: '脉冲', hint: '整段亮度有节奏地脉冲' },
    ],
  },
  waiting: {
    default: 'breathe',
    options: [
      { id: 'breathe', label: '呼吸', hint: '明暗缓慢呼吸，提醒在等审批' },
      { id: 'blink', label: '闪烁', hint: '快速明灭' },
    ],
  },
  done: {
    default: 'flash',
    options: [
      { id: 'flash', label: '闪烁', hint: '完成时闪几下，然后保持微亮' },
      { id: 'solid', label: '常亮', hint: '整段保持常亮' },
    ],
  },
  error: {
    default: 'blink',
    options: [
      { id: 'blink', label: '闪烁', hint: '持续闪烁，直到下一轮' },
      { id: 'solid', label: '常亮', hint: '整段保持常亮' },
    ],
  },
})

export const STANDBY_CATALOG = Object.freeze({
  default: 'dot',
  options: [
    { id: 'dot', label: '常亮单点' },
    { id: 'orbit', label: '巡游' },
    { id: 'breathe', label: '随机呼吸' },
  ],
})

export const STANDBY_MODES = Object.freeze(STANDBY_CATALOG.options.map((option) => option.id))

/**
 * Curated colour ramps, shared by the session accent and the standby palette.
 * The renderer spreads these stops around the ring and interpolates between
 * them, so an arc never shows the stops as hard bands.
 */
export const CURATED_PALETTES = Object.freeze([
  {
    id: 'neon',
    label: '霓虹',
    kind: 'ramp',
    blurb: '青蓝到品红',
    colors: ['#00e5ff', '#7c4dff', '#ff2d95'],
  },
  {
    id: 'sunset',
    label: '日落',
    kind: 'ramp',
    blurb: '玫红到晚霞金',
    colors: ['#ff3d6e', '#ff7a45', '#ffd166'],
  },
  {
    id: 'mint',
    label: '薄荷',
    kind: 'ramp',
    blurb: '青绿到薄荷白',
    colors: ['#2ec4b6', '#4cc9f0', '#a8e6cf'],
  },
  {
    id: 'aurora',
    label: '极光',
    kind: 'ramp',
    blurb: '青绿、天蓝到紫色',
    colors: ['#2dd4bf', '#38bdf8', '#818cf8', '#a855f7'],
  },
  {
    id: 'ember',
    label: '暖光',
    kind: 'ramp',
    blurb: '暖金到珊瑚色',
    colors: ['#ffe2a8', '#ffb56b', '#ff7a59', '#ff5e7a'],
  },
])

/**
 * What a running session's arc is coloured by.
 *
 * `state` and `source` are identity palettes: six state wells, or one well per
 * tool. The curated ramps spread their stops around the ring, and `rainbow`
 * flows the hue wheel. Waiting / done / error ignore the accent and keep their
 * semantic state colour, so the palette only decides the "busy" look.
 */
export const ACCENT_CATALOG = Object.freeze({
  default: 'state',
  options: [
    {
      id: 'state',
      label: '状态色',
      kind: 'state',
      blurb: '按状态取色，一眼看出在做什么',
      colors: [],
    },
    {
      id: 'source',
      label: '来源色',
      kind: 'source',
      blurb: '按工具取色，一眼看出是谁',
      colors: [],
    },
    ...CURATED_PALETTES,
    { id: 'rainbow', label: '彩虹', kind: 'hue', blurb: '色相沿环流动', colors: [] },
  ],
})

export const ACCENT_MODES = Object.freeze(ACCENT_CATALOG.options.map((option) => option.id))

/**
 * What the idle ring is coloured by. `mono` is the standby-only entry and uses
 * the single `standbyColor` well; the curated ramps and rainbow are shared with
 * the session accents, so both pickers speak the same language.
 */
export const STANDBY_PALETTES = Object.freeze({
  default: 'mono',
  options: [
    {
      id: 'mono',
      label: '单色',
      kind: 'mono',
      blurb: '只用下面选的一种颜色',
      colors: [],
    },
    ...CURATED_PALETTES,
    { id: 'rainbow', label: '彩虹', kind: 'hue', blurb: '色相沿环流动', colors: [] },
  ],
})

export const STANDBY_PALETTE_MODES = Object.freeze(
  STANDBY_PALETTES.options.map((option) => option.id),
)

/**
 * id → palette spec. The two catalogues share the curated entries, so the
 * renderer can resolve either selection through one lookup and config
 * validation can accept an accent wherever a palette is expected.
 */
export const PALETTES = Object.freeze(
  Object.fromEntries(
    [...ACCENT_CATALOG.options, ...STANDBY_PALETTES.options].map((option) => [option.id, option]),
  ),
)

export const EFFECTS = Object.freeze(
  Object.fromEntries(
    Object.entries(EFFECT_CATALOG).map(([state, group]) => [
      state,
      group.options.map((option) => option.id),
    ]),
  ),
)

export const EFFECT_DEFAULTS = Object.freeze(
  Object.fromEntries(
    Object.entries(EFFECT_CATALOG).map(([state, group]) => [state, group.default]),
  ),
)

export function capabilities() {
  return {
    version: 2,
    standby: STANDBY_CATALOG,
    accents: ACCENT_CATALOG,
    standbyPalettes: STANDBY_PALETTES,
    effects: Object.fromEntries(
      Object.entries(EFFECT_CATALOG).map(([state, group]) => [
        state,
        { default: group.default, options: group.options },
      ]),
    ),
  }
}
