import { UIContext } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';

/** Default drawing family when user picks System. */
export const SYSTEM_FONT_FAMILY: string = 'System';

export function normalizeSystemFontFamily(name: string): string {
  const trimmed = name.trim();
  if (trimmed.length === 0 ||
    trimmed === 'monospace' ||
    trimmed === 'Monospace' ||
    trimmed === 'System') {
    return SYSTEM_FONT_FAMILY;
  }
  return trimmed;
}

/** Value passed to Canvas / atlas (Drawing understands monospace as system default). */
export function atlasFontFamily(name: string): string {
  const n = normalizeSystemFontFamily(name);
  if (n === SYSTEM_FONT_FAMILY) {
    return 'monospace';
  }
  return n;
}

function pushUnique(out: string[], seen: Set<string>, name: string): void {
  const n = name.trim();
  if (n.length === 0) {
    return;
  }
  if (n === 'monospace' || n === 'Monospace') {
    return;
  }
  if (seen.has(n)) {
    return;
  }
  seen.add(n);
  out.push(n);
}

function descriptorLabel(d: text.FontDescriptor): string {
  if (d.fontFamily !== undefined && d.fontFamily.length > 0) {
    return d.fontFamily;
  }
  if (d.fullName !== undefined && d.fullName.length > 0) {
    return d.fullName;
  }
  return '';
}

function isUsefulSystemFont(d: text.FontDescriptor): boolean {
  if (d.italic !== undefined && d.italic !== 0) {
    return false;
  }
  if (d.symbolic === true) {
    return false;
  }
  const label: string = descriptorLabel(d);
  if (label.length === 0) {
    return false;
  }
  const lower: string = label.toLowerCase();
  if (lower.indexOf('emoji') >= 0 || lower.indexOf('flags') >= 0) {
    return false;
  }
  if (label.indexOf('HarmonyOS') === 0 || label.indexOf('HMOS') === 0) {
    return true;
  }
  if (d.monoSpace === true || lower.indexOf('mono') >= 0) {
    return true;
  }
  if (label.indexOf('Noto Sans Mono') === 0 ||
    label.indexOf('Noto Sans CJK') === 0 ||
    label.indexOf('Noto Sans SC') === 0 ||
    label.indexOf('Noto Sans TC') === 0 ||
    label.indexOf('Noto Sans JP') === 0 ||
    label.indexOf('Noto Sans KR') === 0) {
    return true;
  }
  if (label.indexOf('Noto ') === 0) {
    return false;
  }
  return true;
}

/** Prefer System + mono faces first, then other useful system fonts. */
export async function listSystemFontFamilies(uiContext: UIContext): Promise<string[]> {
  const seen: Set<string> = new Set();
  const out: string[] = [];
  pushUnique(out, seen, SYSTEM_FONT_FAMILY);

  const mono: string[] = [];
  const other: string[] = [];

  try {
    const descriptors: text.FontDescriptor[] = await text.matchFontDescriptors({});
    for (let i = 0; i < descriptors.length; i++) {
      const d = descriptors[i];
      if (!isUsefulSystemFont(d)) {
        continue;
      }
      const name = descriptorLabel(d);
      if (name.length === 0 || seen.has(name) || name === SYSTEM_FONT_FAMILY) {
        continue;
      }
      seen.add(name);
      const lower = name.toLowerCase();
      if (d.monoSpace === true || lower.indexOf('mono') >= 0) {
        mono.push(name);
      } else {
        other.push(name);
      }
    }
  } catch (_e) {
  }

  try {
    const list: string[] = uiContext.getFont().getSystemFontList();
    for (let i = 0; i < list.length; i++) {
      const n = list[i].trim();
      if (n.length === 0 || seen.has(n) || n === SYSTEM_FONT_FAMILY) {
        continue;
      }
      if (n === 'monospace' || n === 'Monospace') {
        continue;
      }
      seen.add(n);
      const lower = n.toLowerCase();
      if (lower.indexOf('mono') >= 0) {
        mono.push(n);
      } else {
        other.push(n);
      }
    }
  } catch (_e) {
  }

  mono.sort();
  other.sort();
  for (let i = 0; i < mono.length; i++) {
    out.push(mono[i]);
  }
  for (let i = 0; i < other.length; i++) {
    out.push(other[i]);
  }
  return out;
}
