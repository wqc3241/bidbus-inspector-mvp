// Top view of a car from the mockup (template.html CAR_SVG, CAR_SIL, CAR_MIRRORS, WHEELS), in its viewBox units. Generated from the mockup data; do not edit by hand.
// A part: place, label, path, kind ('' body, 'gl' glass, 'rf' roof, 'lz' lamp, 'mr' mirror), tap rect (x, y, w, h) or null, name pill rect (x, y, w, h), name lines, lamp or crease path.
typedef CarPart = (String, String, String, String, List<double>?, List<double>, List<String>, String?);

const carSil = 'M180 4C140 4 104 10 90 24C80 34 77 52 76 78C75 100 75 140 76 160C77 172 81 182 81 196L81 316C81 330 76 338 76 352L76 404C76 432 92 448 120 452C140 455 160 456 180 456C200 456 220 455 240 452C268 448 284 432 284 404L284 352C284 338 279 330 279 316L279 196C279 182 283 172 284 160C285 140 285 100 284 78C283 52 280 34 270 24C256 10 220 4 180 4Z';

const carParts = <CarPart>[
  ('Front bumper', 'Front bumper', 'M40 -20H320V64Q180 36 40 64Z', '', [76, -14, 208, 64], [126.6, 20, 106.8, 22], ['Front bumper'], null),
  ('Headlight', 'Left headlight', 'M40 69L110 56.5V94H40Z', 'lz', [62, 56, 48, 38], [-6, 51, 64, 38], ['Head', 'light'], 'M80 88C80 74 88 64 109 60L109 72C96 74 88 80 84 92Z'),
  ('Headlight', 'Right headlight', 'M320 69L250 56.5V94H320Z', 'lz', [250, 56, 48, 38], [302, 51, 64, 38], ['Head', 'light'], 'M280 88C280 74 272 64 251 60L251 72C264 74 272 80 276 92Z'),
  ('Hood', 'Hood', 'M113 56Q180 50 247 56V173Q180 157 113 173Z', '', null, [156.2, 105, 47.6, 22], ['Hood'], 'M140 64Q134 112 140 160M220 64Q226 112 220 160'),
  ('Left front fender', 'Left front fender', 'M40 97H110V174H40Z', '', [62, 97, 48, 77], [-6, 105, 64, 38], ['Front', 'fender'], null),
  ('Right front fender', 'Right front fender', 'M320 97H250V174H320Z', '', [250, 97, 48, 77], [302, 105, 64, 38], ['Front', 'fender'], null),
  ('Windshield', 'Windshield', 'M113 176Q180 160 247 176L224 222Q180 214 136 222Z', 'gl', null, [134, 188, 92, 22], ['Windshield'], null),
  ('Left front door', 'Left front door', 'M40 177H96V262H40Z', '', [62, 214, 34, 48], [-6, 241, 64, 38], ['Front', 'door'], null),
  ('Right front door', 'Right front door', 'M320 177H264V262H320Z', '', [264, 214, 34, 48], [302, 241, 64, 38], ['Front', 'door'], null),
  ('Left front window', 'Left front window', 'M99 186Q99 178 107 178H110.6L134 224.7V262H99Z', 'gl', null, [-6, 199, 64, 38], ['Front', 'window'], null),
  ('Right front window', 'Right front window', 'M261 186Q261 178 253 178H249.4L226 224.7V262H261Z', 'gl', null, [302, 199, 64, 38], ['Front', 'window'], null),
  ('Roof', 'Roof', 'M138 238Q138 225 152 225H208Q222 225 222 238V306Q222 318 208 318H152Q138 318 138 306Z', 'rf', null, [156.2, 261, 47.6, 22], ['Roof'], null),
  ('Left rear door', 'Left rear door', 'M40 265H96V334H40Z', '', [62, 265, 34, 69], [-6, 283, 64, 38], ['Rear', 'door'], null),
  ('Right rear door', 'Right rear door', 'M320 265H264V334H320Z', '', [264, 265, 34, 69], [302, 283, 64, 38], ['Rear', 'door'], null),
  ('Left rear window', 'Left rear window', 'M99 265H134V318.4L111.8 358H107Q99 358 99 350Z', 'gl', null, [-6, 325, 64, 38], ['Rear', 'window'], null),
  ('Right rear window', 'Right rear window', 'M261 265H226V318.4L248.2 358H253Q261 358 261 350Z', 'gl', null, [302, 325, 64, 38], ['Rear', 'window'], null),
  ('Rear glass', 'Rear glass', 'M136 321Q180 328 224 321L247 362Q180 376 113 362Z', 'gl', null, [134, 335, 92, 22], ['Rear glass'], null),
  ('Left quarter panel', 'Left quarter panel', 'M40 337H96V361H110V394H40Z', '', [62, 337, 48, 57], [-6, 367, 64, 38], ['Quarter', 'panel'], null),
  ('Right quarter panel', 'Right quarter panel', 'M320 337H264V361H250V394H320Z', '', [250, 337, 48, 57], [302, 367, 64, 38], ['Quarter', 'panel'], null),
  ('Trunk or liftgate', 'Trunk or liftgate', 'M113 366Q180 380 247 366V413Q180 409 113 413Z', '', null, [152.5, 380, 55, 22], ['Trunk'], null),
  ('Tail light', 'Left tail light', 'M40 397H110V413.5L40 421Z', 'lz', [62, 397, 48, 22], [-6, 409, 64, 38], ['Tail', 'light'], 'M80 404L108 401V410L86 416Q80 412 80 404Z'),
  ('Tail light', 'Right tail light', 'M320 397H250V413.5L320 421Z', 'lz', [250, 397, 48, 22], [302, 409, 64, 38], ['Tail', 'light'], 'M280 404L252 401V410L274 416Q280 412 280 404Z'),
  ('Rear bumper', 'Rear bumper', 'M40 424Q180 404 320 424V480H40Z', '', [76, 414, 208, 60], [130.3, 426, 99.4, 22], ['Rear bumper'], null),
];

// both mirrors are the one place 'Mirror'
const carMirrors = <CarPart>[
  ('Mirror', 'Left mirror', 'M80 182L69 184Q62 185 62 191L63 196Q64 199 70 199L80 197Z', 'mr', [58, 176, 24, 30], [-6, 157, 64, 38], ['Mirror'], null),
  ('Mirror', 'Right mirror', 'M280 182L291 184Q298 185 298 191L297 196Q296 199 290 199L280 197Z', 'mr', [278, 176, 24, 30], [302, 157, 64, 38], ['Mirror'], null),
];

// wheel id, place prefix, centre (x, y), in the mockup order
const carWheels = <(String, String, double, double)>[
  ('lf', 'Left front', 78, 135),
  ('lr', 'Left rear', 78, 372),
  ('rr', 'Right rear', 282, 372),
  ('rf', 'Right front', 282, 135),
];
