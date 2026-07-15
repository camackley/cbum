// Helpers de fecha-día YYYY-MM-DD. El server NUNCA hace math de timezone (overview);
// estas fechas ya vienen calculadas en America/Bogota por el cliente. Solo aritmética de calendario.

const MS_PER_DAY = 86_400_000;

// Parse YYYY-MM-DD a epoch ms en UTC (mediodía-agnóstico: usamos medianoche UTC como ancla estable).
export function dayToUtcMs(date: string): number {
  const [y, m, d] = date.split('-').map(Number);
  return Date.UTC(y!, m! - 1, d!);
}

export function utcMsToDay(ms: number): string {
  const d = new Date(ms);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// Días de calendario entre a y b (b - a). Puede ser negativo.
export function daysBetween(a: string, b: string): number {
  return Math.round((dayToUtcMs(b) - dayToUtcMs(a)) / MS_PER_DAY);
}

export function addDays(date: string, n: number): string {
  return utcMsToDay(dayToUtcMs(date) + n * MS_PER_DAY);
}

// Lista inclusiva de días de start a end.
export function enumerateDays(start: string, end: string): string[] {
  const out: string[] = [];
  const n = daysBetween(start, end);
  for (let i = 0; i <= n; i++) out.push(addDays(start, i));
  return out;
}

// Semana ISO-8601 → 'YYYY-Www'.
export function isoWeek(date: string): string {
  const [y, m, d] = date.split('-').map(Number);
  const dt = new Date(Date.UTC(y!, m! - 1, d!));
  const dayNum = (dt.getUTCDay() + 6) % 7; // Lun=0..Dom=6
  dt.setUTCDate(dt.getUTCDate() - dayNum + 3); // jueves de esta semana ISO
  const isoYear = dt.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(isoYear, 0, 4));
  const ftDayNum = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - ftDayNum + 3);
  const week = 1 + Math.round((dt.getTime() - firstThursday.getTime()) / (7 * MS_PER_DAY));
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}
