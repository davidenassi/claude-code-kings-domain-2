"""Hand-authored macro geography of the King's Domain continent.

Coordinates are normalised: u in [0,1] west->east, v in [0,1] north->south.
The generator adds noise on top of these guides, so they define the *intent*
(where the big lobes, gulfs, ranges and passes are), not the final pixels.
"""

WORLD_W_M = 112000.0
WORLD_H_M = 72000.0

# Land lobes: (u, v, radius_u, radius_v, rotation_deg, weight)
LAND_BLOBS = [
    (0.47, 0.45, 0.25, 0.25, 0.0, 1.00),   # core of the continent
    (0.23, 0.36, 0.13, 0.22, 10.0, 0.95),  # western heartland (germanic)
    (0.14, 0.17, 0.08, 0.09, -25.0, 0.90), # north-western highlands and fjords
    (0.33, 0.16, 0.09, 0.08, 0.0, 0.80),   # northern plains
    (0.63, 0.22, 0.17, 0.12, -8.0, 0.95),  # north-eastern plains (slavic)
    (0.80, 0.16, 0.07, 0.07, 20.0, 0.80),  # north-eastern cape
    (0.87, 0.42, 0.075, 0.22, 4.0, 0.95),  # far east valleys (asian)
    (0.73, 0.40, 0.085, 0.17, 0.0, 0.95),  # eastern march: land bridge carrying the eastern wall
    (0.66, 0.58, 0.07, 0.08, 0.0, 0.85),   # lowlands south of the great lake
    (0.78, 0.72, 0.12, 0.13, 10.0, 0.90),  # south-eastern plateau (arab)
    (0.91, 0.70, 0.05, 0.08, -15.0, 0.75), # arab eastern shore
    (0.56, 0.80, 0.055, 0.12, -14.0, 0.88),# hellenic peninsula
    (0.47, 0.68, 0.07, 0.07, 0.0, 0.80),   # hellenic mainland shoulder
    (0.26, 0.76, 0.075, 0.12, 18.0, 0.92), # latin south-western peninsula
    (0.33, 0.61, 0.09, 0.08, 0.0, 0.85),   # latin mainland
    (0.12, 0.55, 0.05, 0.09, -10.0, 0.80), # western cape
]

# Seas carved into the land: (u, v, radius_u, radius_v, rotation_deg, weight)
SEA_BLOBS = [
    (0.405, 0.880, 0.050, 0.170, 8.0, 1.00),  # southern gulf between latin and hellenic peninsulas
    (0.660, 0.900, 0.045, 0.130, -12.0, 1.00),# gulf between hellenic and arab coasts
    (0.470, 0.080, 0.060, 0.090, 0.0, 1.00),  # northern bay
    (0.030, 0.420, 0.050, 0.120, 0.0, 0.90),  # western sea inlet
    (0.200, 0.575, 0.045, 0.050, 0.0, 0.90),  # western gulf ("Golfo d'Occidente")
    (0.960, 0.560, 0.030, 0.070, 0.0, 0.90),  # eastern bay
    (0.090, 0.050, 0.070, 0.060, 0.0, 0.90),  # north-west fjord sea
    (0.230, 0.050, 0.035, 0.060, 0.0, 0.80),  # northern fjord
    (0.720, 0.080, 0.040, 0.060, 0.0, 0.85),  # north-eastern bay
    (0.840, 0.900, 0.060, 0.060, 0.0, 0.90),  # south-eastern cove
]

# Explicit inland lake basins (lowered terrain so hydrology fills them): (u, v, ru, rv, rot, depth_m)
LAKE_BASINS = [
    (0.600, 0.520, 0.045, 0.030, 20.0, 80.0),  # "Lago Azzurro" between the central and eastern ranges
    (0.300, 0.300, 0.020, 0.014, -10.0, 45.0), # germanic forest lake
]

# Upland regions where hills are strong (u, v, ru, rv, strength); elsewhere plains stay gentle.
HIGHLANDS = [
    (0.15, 0.20, 0.10, 0.12, 1.0),
    (0.40, 0.45, 0.20, 0.10, 0.9),
    (0.78, 0.42, 0.06, 0.25, 1.0),
    (0.72, 0.64, 0.14, 0.08, 0.8),
    (0.55, 0.78, 0.05, 0.12, 0.9),
    (0.26, 0.74, 0.05, 0.08, 0.6),
    (0.60, 0.15, 0.08, 0.06, 0.6),
]

# Mountain ranges: polyline points (u, v), half width (normalised u units), peak factor 0..1,
# passes: list of (u, v, strength 0..1) where the crest is deliberately lowered.
RANGES = [
    {
        "name": "Montes Centrales",
        "points": [(0.24, 0.51), (0.29, 0.48), (0.35, 0.46), (0.41, 0.49), (0.47, 0.48), (0.53, 0.44), (0.58, 0.46)],
        "width": 0.028, "peak": 0.95,
        "passes": [(0.320, 0.468, 0.85), (0.440, 0.487, 0.9), (0.555, 0.448, 0.7)],
    },
    {
        "name": "Muraglia d'Oriente",
        "points": [(0.775, 0.13), (0.790, 0.22), (0.775, 0.33), (0.765, 0.44), (0.780, 0.55), (0.772, 0.63)],
        "width": 0.022, "peak": 1.00,
        "passes": [(0.783, 0.265, 0.85), (0.768, 0.470, 0.9)],
    },
    {
        "name": "Spina Ellenica",
        "points": [(0.520, 0.66), (0.548, 0.74), (0.565, 0.82), (0.553, 0.89)],
        "width": 0.016, "peak": 0.72,
        "passes": [(0.556, 0.780, 0.75)],
    },
    {
        "name": "Alture del Nord-Ovest",
        "points": [(0.09, 0.11), (0.13, 0.18), (0.16, 0.25), (0.14, 0.31)],
        "width": 0.026, "peak": 0.70,
        "passes": [(0.150, 0.215, 0.8)],
    },
    {
        "name": "Ciglio dell'Altopiano",
        "points": [(0.655, 0.625), (0.705, 0.600), (0.760, 0.612), (0.850, 0.650)],
        "width": 0.018, "peak": 0.55,
        "passes": [(0.718, 0.603, 0.9), (0.815, 0.633, 0.8)],
    },
    {
        "name": "Colli d'Occidente",
        "points": [(0.095, 0.44), (0.125, 0.51), (0.150, 0.58)],
        "width": 0.022, "peak": 0.38,
        "passes": [],
    },
    {
        "name": "Monti Slavi",
        "points": [(0.565, 0.14), (0.600, 0.19), (0.640, 0.23)],
        "width": 0.016, "peak": 0.42,
        "passes": [(0.600, 0.190, 0.7)],
    },
    {
        "name": "Serre Latine",
        "points": [(0.235, 0.70), (0.255, 0.77), (0.285, 0.83)],
        "width": 0.014, "peak": 0.40,
        "passes": [],
    },
]

# Climate shaping
ARID_CENTERS = [
    (0.79, 0.76, 0.13, 0.12, 0.80),  # (u, v, ru, rv, strength) south-eastern desert
    (0.93, 0.66, 0.05, 0.08, 0.45),
    (0.66, 0.66, 0.06, 0.05, 0.35),  # dry leeward basin behind the plateau edge
]
WET_CENTERS = [
    (0.66, 0.22, 0.10, 0.06, 0.20),  # north-eastern marshy plains
    (0.22, 0.30, 0.12, 0.14, 0.18),  # germanic forests
    (0.87, 0.40, 0.06, 0.18, 0.15),  # monsoon valleys of the far east
]

# Culture macro regions: (culture_id, religion_id, u, v, weight). Provinces take the culture of the
# nearest weighted centre with noise, so frontiers are irregular and mixed.
CULTURE_CENTERS = [
    ("germanic", "catholic", 0.18, 0.26, 1.00),
    ("germanic", "catholic", 0.35, 0.30, 0.85),
    ("latin", "catholic", 0.24, 0.70, 1.00),
    ("latin", "catholic", 0.33, 0.58, 0.80),
    ("slavic", "orthodox", 0.63, 0.20, 1.00),
    ("slavic", "orthodox", 0.52, 0.33, 0.80),
    ("hellenic", "orthodox", 0.55, 0.78, 1.00),
    ("hellenic", "orthodox", 0.47, 0.64, 0.80),
    ("arab", "muslim", 0.78, 0.74, 1.00),
    ("arab", "muslim", 0.66, 0.60, 0.75),
    ("asian", "hindu", 0.87, 0.33, 1.00),
    ("asian", "hindu", 0.88, 0.53, 0.85),
]

# Religious minorities that break the culture=religion pattern: (u, v, radius, religion)
RELIGION_POCKETS = [
    (0.42, 0.60, 0.05, "orthodox"),   # latin-orthodox borderland
    (0.48, 0.38, 0.05, "catholic"),   # slavic-catholic march
    (0.62, 0.68, 0.04, "orthodox"),   # arab lands with orthodox communities
    (0.70, 0.45, 0.05, "muslim"),     # slavic/hellenic frontier with muslim towns
    (0.80, 0.22, 0.04, "orthodox"),   # asian frontier monasteries
]

WORLD_SEED = 1230  # fixed: the official map is generated once and committed

