import 'country_codes.dart';

/// Focus coordinates (capital / main city) for countries the vault knows
/// about. Small territories missing from countries-110m (HK, SG) still get a
/// node position from here; others fall back to their polygon centroid.
const countryFocus = <String, (double, double)>{
  'CN': (116.3972, 39.9075),
  'GB': (-0.1257, 51.5085),
  'HK': (114.1850, 22.3050),
  'US': (-74.0167, 40.7167),
  'JP': (139.6500, 35.6764),
  'SG': (103.8198, 1.3521),
  'DE': (13.4050, 52.5200),
  'AU': (151.2093, -33.8688),
  'FR': (2.3522, 48.8566),
  'KR': (126.9780, 37.5665),
  'TW': (121.5654, 25.0330),
  'CA': (-79.3832, 43.6532),
  'TH': (100.5018, 13.7563),
  'MY': (101.6869, 3.1390),
  'RU': (37.6173, 55.7558),
  'IN': (77.2090, 28.6139),
  'AE': (55.2708, 25.2048),
  'NL': (4.9041, 52.3676),
  'MO': (113.5439, 22.1987),
};

String countryLabel(String code) => countryNamesZh[code] ?? code;
