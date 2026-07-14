-- Catálogo inicial de ejercicios (28). id = slug estable. Nombres en español.
-- updated_at = 0 en el seed; los writes reales del server lo sobrescriben con now().
INSERT INTO exercises (id, name, muscle_group, pattern, equipment, increment_kg, updated_at, deleted) VALUES
-- Pecho
('barbell-bench-press',      'Press banca con barra',        'chest',      'horizontal_push', 'barbell',   2.5, 0, 0),
('incline-db-press',         'Press inclinado con mancuernas','chest',      'horizontal_push', 'dumbbell',  2.0, 0, 0),
('machine-chest-press',      'Press de pecho en máquina',    'chest',      'horizontal_push', 'machine',   5.0, 0, 0),
('cable-fly',                'Aperturas en polea',           'chest',      'isolation',       'cable',     2.5, 0, 0),
-- Espalda
('pull-up',                  'Dominadas',                    'back',       'vertical_pull',   'bodyweight',2.5, 0, 0),
('lat-pulldown',             'Jalón al pecho',               'back',       'vertical_pull',   'cable',     5.0, 0, 0),
('barbell-row',              'Remo con barra',               'back',       'horizontal_pull', 'barbell',   2.5, 0, 0),
('seated-cable-row',         'Remo sentado en polea',        'back',       'horizontal_pull', 'cable',     5.0, 0, 0),
('machine-row',              'Remo en máquina',              'back',       'horizontal_pull', 'machine',   5.0, 0, 0),
-- Hombro
('overhead-press',           'Press militar con barra',      'shoulders',  'vertical_push',   'barbell',   2.5, 0, 0),
('db-shoulder-press',        'Press de hombro con mancuernas','shoulders', 'vertical_push',   'dumbbell',  2.0, 0, 0),
('db-lateral-raise',         'Elevaciones laterales con mancuernas','shoulders','isolation',  'dumbbell',  1.0, 0, 0),
('cable-lateral-raise',      'Elevaciones laterales en polea','shoulders', 'isolation',       'cable',     1.0, 0, 0),
('reverse-pec-deck',         'Pájaros en máquina (deltoide posterior)','shoulders','isolation','machine',  5.0, 0, 0),
-- Bíceps
('db-curl',                  'Curl con mancuernas',          'biceps',     'isolation',       'dumbbell',  1.0, 0, 0),
('ez-bar-curl',              'Curl con barra Z',             'biceps',     'isolation',       'barbell',   2.5, 0, 0),
('cable-curl',               'Curl en polea',                'biceps',     'isolation',       'cable',     2.5, 0, 0),
-- Tríceps
('cable-pushdown',           'Extensión de tríceps en polea','triceps',    'isolation',       'cable',     2.5, 0, 0),
('overhead-cable-extension', 'Extensión de tríceps sobre la cabeza en polea','triceps','isolation','cable',2.5, 0, 0),
('skull-crusher',            'Extensión de tríceps tumbado (rompecráneos)','triceps','isolation','barbell', 2.5, 0, 0),
-- Pierna
('barbell-back-squat',       'Sentadilla con barra',         'quads',      'squat',           'barbell',   2.5, 0, 0),
('hack-squat',               'Sentadilla hack',              'quads',      'squat',           'machine',   5.0, 0, 0),
('leg-press',                'Prensa de pierna',             'quads',      'squat',           'machine',   5.0, 0, 0),
('romanian-deadlift',        'Peso muerto rumano',           'hamstrings', 'hinge',           'barbell',   2.5, 0, 0),
('leg-extension',            'Extensión de cuádriceps',      'quads',      'isolation',       'machine',   5.0, 0, 0),
('seated-leg-curl',          'Curl femoral sentado',         'hamstrings', 'isolation',       'machine',   5.0, 0, 0),
('hip-thrust',               'Empuje de cadera',             'glutes',     'hinge',           'barbell',   5.0, 0, 0),
('standing-calf-raise',      'Elevación de gemelos de pie',  'calves',     'isolation',       'machine',   5.0, 0, 0);
