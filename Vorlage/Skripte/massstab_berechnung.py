"""
Maßstabsberechnung: Drohnenflug → Campus-Testfeld
===================================================
Bestimmt, welche Testfeld-Durchmesser bei Handkamera-Höhe
die gleiche Pixelabdeckung ergeben wie reale Kabel aus Drohnenhöhe.
"""

# === Kamera-Parameter (typische Drohne, z.B. DJI Mavic 3 / Mini 4 Pro) ===
# 1"-Sensor oder 4/3-Sensor
cameras = {
    "DJI Mini 4 Pro (1/1.3\")": {
        "sensor_width_mm": 12.7,
        "focal_length_mm": 6.72,
        "image_width_px": 4032,
    },
    "DJI Mavic 3 (4/3\")": {
        "sensor_width_mm": 17.3,
        "focal_length_mm": 12.29,
        "image_width_px": 5280,
    },
    "Typische Handy-Kamera (1/1.7\")": {
        "sensor_width_mm": 9.5,
        "focal_length_mm": 6.0,
        "image_width_px": 4000,
    },
    "Sony Alpha (APS-C)": {
        "sensor_width_mm": 23.5,
        "focal_length_mm": 24.0,
        "image_width_px": 6000,
    },
}

# === Szenarien ===
# Real: Drohne bei 10m Höhe über Trasse
# Campus: Kamera auf Stativ/Handheld bei 1.5m / 2.0m / 3.0m Höhe
flight_height_m = 10.0
campus_heights_m = [1.5, 2.0, 3.0]

# Reale Kabel-Durchmesser
real_cables = {
    "Lichtwellenleiter (LWL)": 0.05,    # 5 cm
    "Steuerkabel": 0.08,                 # 8 cm
    "Mittelspannungskabel": 0.12,        # 12 cm
    "DC-Erdkabel (525 kV)": 0.20,       # 20 cm
}

def gsd(sensor_width_mm, focal_length_mm, height_m, image_width_px):
    """Ground Sampling Distance in mm/pixel"""
    return (sensor_width_mm * height_m * 1000) / (focal_length_mm * image_width_px)

def pixels_for_diameter(diameter_m, gsd_mm):
    """Wie viele Pixel bedeckt ein Objekt mit gegebenem Durchmesser?"""
    return (diameter_m * 1000) / gsd_mm

def equivalent_diameter(target_pixels, gsd_mm):
    """Welcher Durchmesser [mm] ergibt die gleiche Pixelanzahl bei anderem GSD?"""
    return target_pixels * gsd_mm

print("=" * 80)
print("MASSSTABSBERECHNUNG: Drohnenflug → Campus-Testfeld")
print("=" * 80)

for cam_name, cam in cameras.items():
    print(f"\n{'─' * 80}")
    print(f"📷 Kamera: {cam_name}")
    print(f"   Sensor: {cam['sensor_width_mm']}mm, Brennweite: {cam['focal_length_mm']}mm, {cam['image_width_px']}px")
    print(f"{'─' * 80}")
    
    # GSD bei Drohnenhöhe
    gsd_drone = gsd(cam["sensor_width_mm"], cam["focal_length_mm"], 
                    flight_height_m, cam["image_width_px"])
    print(f"\n  Drohne bei {flight_height_m}m Höhe:")
    print(f"  GSD = {gsd_drone:.2f} mm/px")
    print(f"  {'Kabel':<30} {'⌀ real':>8} {'Pixel':>8}")
    print(f"  {'─'*50}")
    
    cable_pixels = {}
    for cable_name, diameter in real_cables.items():
        px = pixels_for_diameter(diameter, gsd_drone)
        cable_pixels[cable_name] = px
        print(f"  {cable_name:<30} {diameter*100:>6.1f} cm {px:>7.1f} px")
    
    # Äquivalente Durchmesser auf Campus
    for campus_h in campus_heights_m:
        gsd_campus = gsd(cam["sensor_width_mm"], cam["focal_length_mm"],
                        campus_h, cam["image_width_px"])
        scale_factor = flight_height_m / campus_h
        
        print(f"\n  Campus-Kamera bei {campus_h}m Höhe:")
        print(f"  GSD = {gsd_campus:.2f} mm/px | Skalierungsfaktor: 1:{scale_factor:.1f}")
        print(f"  {'Kabel':<30} {'Pixel':>8} {'⌀ Campus':>10} {'Testobjekt':>25}")
        print(f"  {'─'*80}")
        
        for cable_name, px in cable_pixels.items():
            eq_d_mm = equivalent_diameter(px, gsd_campus)
            
            # Vorschlag Testobjekt
            if eq_d_mm > 30:
                obj = "KG-Rohr / HT-Rohr"
            elif eq_d_mm > 10:
                obj = "Gartenschlauch"
            elif eq_d_mm > 3:
                obj = "Seil / dicke Schnur"
            else:
                obj = "Nylonschnur / Draht"
            
            print(f"  {cable_name:<30} {px:>7.1f} px {eq_d_mm:>8.1f} mm  → {obj}")

# === Empfehlung ===
print(f"\n{'=' * 80}")
print("EMPFEHLUNG FÜR TESTFELD (Kamera bei ~2m Höhe)")
print("=" * 80)

# Berechnung mit DJI Mavic 3 als Referenz (häufigste Drohne)
cam = cameras["DJI Mavic 3 (4/3\")"]
gsd_d = gsd(cam["sensor_width_mm"], cam["focal_length_mm"], flight_height_m, cam["image_width_px"])
gsd_c = gsd(cam["sensor_width_mm"], cam["focal_length_mm"], 2.0, cam["image_width_px"])

print(f"\nReferenz: DJI Mavic 3 bei 10m → GSD = {gsd_d:.2f} mm/px")
print(f"Campus:   Gleiche Kamera bei  2m → GSD = {gsd_c:.2f} mm/px")
print(f"Faktor:   {flight_height_m/2.0:.0f}x (alle Durchmesser durch {flight_height_m/2.0:.0f} teilen)\n")

print(f"{'Real (Drohne 10m)':<30} {'⌀ real':>8} {'→':>3} {'⌀ Campus (2m)':>14} {'Testobjekt':>25}")
print(f"{'─'*85}")
for cable_name, diameter in real_cables.items():
    eq = diameter / (flight_height_m / 2.0) * 1000  # mm
    if eq > 30:
        obj = "KG-Rohr DN" + str(int(round(eq/10)*10))
    elif eq > 10:
        obj = "Gartenschlauch / PE-Rohr"
    elif eq > 3:
        obj = "Paketschnur / Seil"
    else:
        obj = "Nylonschnur"
    print(f"  {cable_name:<28} {diameter*100:>6.1f} cm  →  {eq:>10.1f} mm    {obj}")

print(f"\n{'=' * 80}")
print("FAZIT: Bei 2m Kamerahöhe und Skalierungsfaktor 5x:")
print("  • 20 cm DC-Kabel  → 40 mm Testobjekt (Gartenschlauch ⌀ 40mm oder PE-Rohr)")
print("  • 12 cm Kabel     → 24 mm Testobjekt (Gartenschlauch ⌀ 25mm)")
print("  •  8 cm Kabel     → 16 mm Testobjekt (Gartenschlauch ⌀ 16mm)")  
print("  •  5 cm LWL       → 10 mm Testobjekt (dicke Schnur / dünner Schlauch)")
print("=" * 80)
