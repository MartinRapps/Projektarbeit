# Implementierungs- und Validierungsplan: Maskenkonsistentes SuGaR-Meshing

> **Status:** Artefakte im Coarse-Mesh lokalisiert; kontrollierte Ablationen stehen aus.  
> **Aktualisiert:** 16.07.2026

## 1. Ziel und Abgrenzung

Dieser Plan beschreibt ausschließlich die aktuelle Objekt-Rekonstruktion mit
maskenkonsistentem SuGaR. Er ergänzt die historischen Scope- und
Machbarkeitsdokumente, ersetzt sie aber nicht. Untersucht wird, in welcher
SuGaR-Stufe die großflächigen Restflächen der Brillenrekonstruktion erstmals
entstehen. Eine aggressive nachträgliche Mesh-Beschneidung ist ausdrücklich
kein Ersatz für diese Ursachenanalyse.

## 2. Reproduzierbarer Ausgangszustand

| Merkmal | Aktueller Stand |
|---|---|
| Eingabe | Gefilterte STS-Objektwolke `point_cloud_filtered.ply` mit 6.175 Punkten; Standard-SuGaR-Eingang ist die Hochopazitätskopie `point_cloud_filtered_opacity999999.ply` |
| Kameras und Masken | 699 registrierte Kameras und nichtleere Masken bei $768 \times 432$ Pixeln; mit `--eval=True` werden die Indizes $i \bmod 8=0$ als 88 Eval-Ansichten und die übrigen 611 als Trainingsansichten verwendet |
| Coarse-Regularisierung | `dn_consistency`, Zielzähler 15.000; Start bei Zähler 6.999, also rund 8.001 neue Updates |
| Refinement | Profil `medium`, 7.000 Iterationen |
| Mesh-Zielgröße | 1.000.000 Vertices |
| Oberflächenstichproben | Ziel 10.000.000 über 611 Trainingsansichten vor Poisson-Rekonstruktion; tatsächlich verfügbare Zahl kann kleiner sein |
| RGB-Supervision | `default`-Maske mit 2 px zusätzlicher Dilatation |
| DN-Supervision | nicht dilatierte `middle`-Maske |
| UV-Supervision | `default`-Maske mit 2 px zusätzlicher Dilatation |
| Ergebnis | Vollständiger Lauf mit Coarse-Checkpoint, Coarse-Mesh, verfeinerter PLY und texturiertem OBJ |

Die hierarchischen Masken und die SuGaR-Dilatation sind getrennte Konzepte:

- `default` ist die ursprüngliche SAM-Maske.
- `middle` ist die einmal mit einem $5 \times 5$-Kernel erodierte Maske.
- `small` ist die zweimal erodierte Kernmaske.
- Die 2 px RGB- und UV-Dilatation erweitert anschließend erst die jeweilige
  bereits gewählte Maske. Sie verändert nicht die DN-Maske.

Die gleiche ursprüngliche SAM-Maske hat in STS und SuGaR unterschiedliche
Wirkungen. STS nutzt sie für Objekt-IDs und damit für die gefilterte
Eingabe-PLY. SuGaR nutzt sie später erneut zur Bildsupervision. Deshalb
beweist eine visuell saubere Eingabe-PLY nicht, dass die 2-px-RGB-Dilatation
im nachfolgenden Coarse- oder Refinement-Loss unschädlich ist.

Die DN-Maske ist eine dritte, davon getrennte Anwendung: `DN` bedeutet
Depth-Normal Consistency. `NORMAL_MASK_LEVEL=middle` lädt die einmal mit einem
$5 \times 5$-Kernel erodierte SAM-Maske ohne Dilatation. Sie markiert nur die
Pixel, deren Konsistenzfehler in den DN-Loss eingeht; sie enthält weder eine
gemessene Tiefe noch eine externe Normalenreferenz. SuGaR leitet eine Normale
aus seiner gerenderten Tiefenkarte ab und vergleicht sie mit der ebenfalls
gerenderten Gaussian-Normale. Der gewichtete Fehler ist nur im konservativen
Objektinneren aktiv, beginnt erst nach Coarse-Zählerstand 9.000 mit Faktor 0,05
und lässt den ein Pixel breiten Bildrand aus. Die DN-Maske filtert weder die
STS-Eingabewolke noch UV-Farben und wird im aktuellen Refinement nicht genutzt.

## 3. Beobachtungen und belastbare Schlussfolgerung

Die gefilterte Eingabe-PLY wurde in kamera-ausgerichteten Ansichten qualitativ
gegen die Brillengeometrie geprüft. Sie enthält keine auffälligen frei
schwebenden oder groß abgelösten Splats. Der visuell geschätzte Abstand liegt
grob im Bereich bis etwa 1 mm. Dies ist keine kalibrierte Messung und darf
weder als Toleranzangabe noch als metrischer Geometrienachweis verwendet
werden.

Die Restflächen sind im Coarse-Mesh bereits sichtbar und treten auch in der
verfeinerten Gaussian-PLY auf. Das finale texturierte OBJ ist somit nicht ihr
erster Auftretensort. Die `.pt`-Dateien sind nicht direkt visualisierbare
PyTorch-Checkpoints; sie werden als reproduzierbare Zustände aufbewahrt, sind
für diese sichtbasierte Stufenlokalisierung aber nicht nötig.

**Falsifizierbare Arbeitshypothese:** Da die Eingabe qualitativ unauffällig
ist und die Flächen im Coarse-Mesh erstmals sichtbar werden, entstehen sie im
Zusammenspiel aus Coarse-Regularisierung und Oberflächengewinnung. Dazu zählen
die Oberflächenabtastung, Poisson-Rekonstruktion, Dichtebereinigung,
Decimation und Projektion der Mesh-Vertices auf Oberflächenpunkte. Diese
Hypothese weist noch keinen einzelnen Teilmechanismus als Ursache nach.

Die verfeinerte PLY widerlegt diese Hypothese nicht: Das Refinement bindet seine
Gaussians an das vorhandene Coarse-Mesh. Vorhandene fehlerhafte Flächen können
daher übernommen oder verstärkt werden.

Die RGB-Dilatation bleibt ausdrücklich eine zweite, nicht ausgeschlossene
Hypothese: `MASK_DILATION_PX=2` erweitert die RGB-Maske vor dem maskierten
L1+DSSIM-Loss im Coarse-Training und im Refinement. Bei unsicheren
Silhouetten kann sie zusätzliche Hintergrundpixel beaufsichtigen und damit
Geometrie indirekt beeinflussen. Dagegen ist
`TEXTURE_MASK_DILATION_PX` nur im nachgelagerten UV-Baking wirksam; sie kann
das Coarse-Mesh oder die verfeinerte PLY nicht verursachen.

## 3.1 Entstehung des Coarse-Meshes

1. SuGaR initialisiert die trainierbaren Gaussians aus der gefilterten,
  privaten STS-Kopie und optimiert gerenderte RGB-Bilder gegen die
  Originalbilder innerhalb der RGB-Maske.
2. Der lokale `dn_consistency`-Trainer setzt seinen Zähler nach der
  STS-Initialisierung auf 6.999. Der Referenzwert 15.000 bedeutet deshalb
  ungefähr $15000-6999=8001$ neue Optimierungsupdates.
3. Maskierter RGB-Loss läuft während der gesamten Coarse-Optimierung.
  Entropieregularisierung ist zwischen Zählerstand 7.000 und 9.000 aktiv.
  Erst danach werden SDF-Terme und Depth-Normal Consistency zugeschaltet.
4. Die DN-Consistency vergleicht innerhalb der nicht dilatierten
  `middle`-Maske die aus der gerenderten Tiefe abgeleitete Normale mit der
  Gaussian-Normale. Sie stabilisiert die lokale Oberflächenorientierung,
  nachdem die photometrische Darstellung zunächst Zeit zur Stabilisierung
  erhalten hat. Dies ist eine lokale Curriculum-Konfiguration, kein
  universeller SuGaR-Grenzwert.
5. Die Extraktion lädt anschließend den Coarse-Checkpoint und keine
  2D-Masken. Sie verwirft Gaussians mit niedriger Opazität, sampelt
  Oberflächenpunkte samt Normalen aus den 611 Trainingskamera-Renderings,
  rekonstruiert aus
  ihnen ein Poisson-Mesh, entfernt schwach gestützte Poisson-Vertices,
  dezimiert und projiziert optional die verbleibenden Vertices zurück auf
  Oberflächenstichproben.

`POISSON_DEPTH` ist die Oktree-Auflösung der Poisson-Rekonstruktion. Ein hoher
Wert wie 10 kann feine Bügel erhalten, aber auch kleine fehlerhafte Flächen
auflösen und teuer sein. Ein Wert wie 8 ist eine diagnostische, gröbere
Variante; er kann Artefakte abschwächen, aber auch reale dünne Geometrie
verlieren. `MESH_VERTICES` greift erst nach der Poisson-Rekonstruktion bei der
Decimation ein. Für die tatsächlich teure Oberflächenabtastung ist
`SURFACE_SAMPLE_COUNT` der direktere Laufzeithebel; niedrigere Werte sind nur
für Screening-Ergebnisse geeignet.

Die $1{:}8$-Aufteilung folgt dem SuGaR-Wrapper: Bei `eval_split=True` werden
die Kameras mit `i % 8 == 0` in die Testliste und alle übrigen in die
Trainingsliste aufgenommen. Das erklärt exakt $88=\lceil699/8\rceil$ Eval- und
$611$ Trainingsansichten. Ihr Zweck ist eine getrennte Rendering-Evaluation,
nicht ein automatisch erzeugter Geometrienachweis. Im aktuellen Runner bleibt
der Split für referenzgleiche Ablationen unverändert; ein All-View-Lauf wäre ein
separates Experiment.

Die erste ausgeführte Checkpoint-Ablation liegt unter
`data/sugar_output/masked_7000_dn_consistency_medium/coarse_mesh_ablation/validation_prompt_probe/`.
Sie verwendete den bestehenden `15000.pt`-Checkpoint mit Poisson-Tiefe 10,
50.000 Zielvertices, 10.000.000 angeforderten Stichproben und Vertexprojektion.
Sie erzeugte ausschließlich ein Coarse-Mesh; weder bestehende Ergebnisse noch
Coarse-Checkpoint, Refinement, UV-Textur oder Crop wurden verändert. Der Lauf
verarbeitete 611 Trainingsansichten und sammelte 9.424.416 gültige
Oberflächenpunkte.

Die anschließende Variante
`coarse_mesh_ablation/depth8_v50000/` ist ebenfalls ein reines Coarse-Mesh aus
dem unveränderten `15000.pt`-Checkpoint. Sie verwendet Poisson-Tiefe 8 und
50.000 Zielvertices. Nach visueller Inspektion wirkt sie geordneter und für eine
schnelle Artefaktbeurteilung brauchbar, zeigt die Restflächen aber weiterhin.
Da Tiefe und Vertexzahl gegenüber der Referenz gemeinsam geändert wurden, ist
das keine Einzelursachenaussage. Der nächste auflösungsbezogene Vergleich hält
Tiefe 8 fest und erhöht nur das Vertexziel:

```bash
SOURCE_RUN_TAG=masked_7000_dn_consistency_medium \
COARSE_MESH_ABLATION_TAG=depth8_v500000 \
MESH_VERTICES=500000 \
POISSON_DEPTH=8 \
./run_coarse_mesh_ablation.sh
```

## 4. Prüfsequenz ohne neuen Langlauf

Vor jeder neuen Optimierung werden die vorhandenen Artefakte in identischen
kamera-ausgerichteten Ansichten verglichen und in einer Befundtabelle erfasst:

| Stufe | Artefakt | Zu protokollieren |
|---|---|---|
| A | gefilterte Eingabe-PLY | Nähe zur Brille, abgelöste Splats |
| B | Coarse-Mesh-PLY | erstes Auftreten, Lage und Form der Restflächen |
| C | verfeinerte Gaussian-PLY | Übernahme, Verstärkung oder neue Flächen |
| D | texturiertes OBJ | ausschließlich Geometrie oder nur Textur-/Exporteffekt |

Wenn B die erste auffällige Stufe bleibt, wird kein UV- oder OBJ-Parameter als
Hauptreparatur behandelt. Stattdessen werden die Extraktionsparameter jeweils
einzeln aus dem vorhandenen Coarse-Checkpoint untersucht. Besonders relevant
sind Poisson-Tiefe, Dichtequantil, Projektion auf Oberflächenpunkte und
Decimation. Die einzelnen Varianten müssen getrennte Ausgabeordner erhalten.
Der Runner `run_coarse_mesh_ablation.sh` verwendet dafür das vorhandene
`15000.pt`-Artefakt, ohne Coarse-Optimierung, Refinement, Texturierung oder Crop
erneut auszuführen. Eine erste schnellere Referenzextraktion kann so erfolgen:

```bash
SUGAR_RUN_TAG=masked_7000_dn_consistency_medium \
SOURCE_RUN_TAG=masked_7000_dn_consistency_medium \
COARSE_MESH_ABLATION_TAG=depth10_v50000 \
MESH_VERTICES=50000 \
POISSON_DEPTH=10 \
./run_coarse_mesh_ablation.sh
```

Eine Poisson-Variante wird getrennt abgelegt, damit ihr Befund nicht mit der
Referenz vermischt wird:

```bash
SOURCE_RUN_TAG=masked_7000_dn_consistency_medium \
COARSE_MESH_ABLATION_TAG=depth8_v50000 \
MESH_VERTICES=50000 \
POISSON_DEPTH=8 \
./run_coarse_mesh_ablation.sh
```

Die beiden Befehle erzeugen jeweils ausschließlich ein neues Coarse-Mesh-PLY.
Sie erzeugen kein Refined Mesh, führen keine Texturierung aus und verändern
weder die Masken noch den Coarse-Checkpoint. Der erste ist eine kleinere
Decimationsvariante bei unveränderter Poisson-Tiefe; der zweite isoliert bei
gleicher Vertexzahl die gröbere Poisson-Tiefe. Eine schnelle, aber nicht
finale Stichproben-Screening-Variante muss ihren reduzierten Stichprobenumfang
im Tag dokumentieren:

```bash
SOURCE_RUN_TAG=masked_7000_dn_consistency_medium \
COARSE_MESH_ABLATION_TAG=depth8_v50000_samples2m \
MESH_VERTICES=50000 \
POISSON_DEPTH=8 \
SURFACE_SAMPLE_COUNT=2000000 \
./run_coarse_mesh_ablation.sh
```

## 5. Kontrollierte Null-Dilatations-Ablation

Der erste neue Vollauf isoliert die zusätzliche Rand-Supervision. Er verwendet
einen neuen Tag, deaktiviert den nachgelagerten Crop und ändert nur RGB- und
UV-Dilatation:

```bash
SUGAR_RUN_TAG=masked_7000_dn_consistency_no_dilation \
MASK_DILATION_PX=0 \
TEXTURE_MASK_DILATION_PX=0 \
RUN_CONSENSUS_CROP=0 \
./run_masked_sugar.sh
```

Für die zeitkritische erste geometrische Aussage ist der fokussierte
Coarse-only-Volltrainingslauf besser geeignet. Er ändert nur die RGB-Dilatation
gegenüber der Referenz und endet nach dem Coarse-PLY:

```bash
SUGAR_RUN_TAG=masked_7000_dn_consistency_coarse_no_rgb_dilation \
MASK_DILATION_PX=0 \
STOP_AFTER_COARSE_MESH=1 \
RUN_CONSENSUS_CROP=0 \
./run_masked_sugar.sh
```

`TEXTURE_MASK_DILATION_PX` ist in diesem Modus absichtlich nicht gesetzt,
denn UV-Baking wird nicht erreicht und kann die Coarse-Geometrie nicht
beeinflussen. Der vollständige Null-Dilatationslauf oben bleibt sinnvoll, wenn
anschließend auch die verfeinerte PLY und das texturierte OBJ verglichen werden
sollen.

Für genau diesen vollständigen Vergleich muss nicht erst ein Coarse-only-Tag
erzeugt werden. Ein neuer vollständiger Lauf bewahrt sein Coarse-PLY und führt
anschließend Refinement und UV-Baking aus; die Coarse-Datei wird nur gelesen,
nicht ersetzt. Er ändert gegenüber der Referenz nur die RGB-Dilatation:

```bash
SUGAR_RUN_TAG=masked_7000_dn_consistency_no_rgb_dilation_full \
MASK_DILATION_PX=0 \
STOP_AFTER_COARSE_MESH=0 \
RUN_CONSENSUS_CROP=0 \
./run_masked_sugar.sh
```

`TEXTURE_MASK_DILATION_PX` bleibt dabei absichtlich beim Referenzwert 2. So
untersucht der Lauf nur die RGB-Randsupervision in Coarse und Refinement und
liefert unter einem Tag sowohl Coarse-PLY als auch verfeinerte PLY und OBJ. Ein
bereits mit `STOP_AFTER_COARSE_MESH=1` beendeter Tag wird durch den Runner nicht
fortgesetzt; er bleibt als separater Coarse-only-Befund erhalten.

Unverändert bleiben die gefilterte Eingabe-PLY, `dn_consistency`, die
nicht dilatierte `middle`-Maske für DN, Kameras, Zielzähler 15.000,
10.000.000 Oberflächenstichproben, 7.000 Refinement-Iterationen und das
Mesh-Ziel von 1.000.000 Vertices. Der Tag muss neu sein; `REPLACE=1` wird für
diesen Vergleich nicht verwendet. Der Test prüft damit die RGB-Randsupervision
in Coarse und Refinement. Der gleichzeitig auf null gesetzte UV-Wert prüft nur,
ob die Texturansicht den Vergleich verfälscht; UV ist kein Loss und keine
Geometrieursache. Die DN-Maske wird nicht verändert.

| Ergebnis der Ablation | Schlussfolgerung |
|---|---|
| Restflächen unverändert im Coarse-Mesh | 2 px RGB-Dilatation ist keine Primärursache |
| Restflächen geringer, aber Coarse-Mesh weiterhin auffällig | Maskenrand trägt bei; Extraktion bleibt zu prüfen |
| Nur Textur ändert sich | UV-Dilatation beeinflusst die Erscheinung, nicht die Geometrie |
| Restflächen erst nach Refinement | Refinement-Supervision wird als nächstes isoliert |

## 6. Laufzeitbewusste Folgeexperimente

Ein Millionen-Vertex-Mesh und das vollständige Refinement sind für einen
ersten Ursachencheck nicht zwingend. Zuerst wird daher die Mesh-Extraktion aus
dem bereits vorhandenen Coarse-Checkpoint mit kleinerer Zielgröße geprüft,
bevor ein erneutes vollständiges Coarse-Training gestartet wird. Für die
Brille ist eine Zielgröße von 10.000 Vertices als schneller Sichttest möglich,
aber für dünne Bügel und die Brillenkontur wahrscheinlich zu grob. Ein Bereich
von 25.000 bis 100.000 Vertices ist ein sinnvollerer erster Kompromiss. Erst
wenn die Topologie und Artefaktlage damit verständlich sind, wird die für eine
spätere Centerline- oder metrische Auswertung erforderliche Auflösung erhöht.

Die 15.000 Coarse-Iterationen sind ein im lokalen SuGaR-Fork fest gesetzter
Zielzähler, keine nachgewiesene Mindestzahl neuer Updates für dieses kleine
Objekt. Wegen des Starts bei 6.999 bedeutet ein Zielwert von 7.500 nur etwa
501 neue Updates und keine DN-Consistency. Eine verkürzte Variante muss
mindestens Zählerstand 9.001 erreichen; sinnvoller ist 12.000, weil dann etwa
3.000 Updates mit DN- und SDF-Term vorliegen. Der Runner unterstützt dafür bei
`dn_consistency` optional `COARSE_ITERATIONS`; `MESH_VERTICES` steuert die
Decimationszielgröße und `SURFACE_SAMPLE_COUNT` die teure
Kameraoberflächenabtastung. Ein schneller, bewusst nicht mit der Referenz
vergleichbarer Screening-Lauf kann beispielsweise so gestartet werden:

```bash
SUGAR_RUN_TAG=masked_7000_dn_consistency_screening_c12000_v50000 \
COARSE_ITERATIONS=12000 \
MESH_VERTICES=50000 \
SURFACE_SAMPLE_COUNT=2000000 \
REFINEMENT_TIME=short \
RUN_CONSENSUS_CROP=0 \
./run_masked_sugar.sh
```

Dieser Befehl startet im Unterschied zur Checkpoint-Ablation die gesamte Kette
neu: Coarse-Training, Coarse-Mesh, kurzes Refinement und UV-Texturierung. Der
Crop wird nur übersprungen, nicht ausgeführt. Da die Dilatationsvariablen hier
nicht gesetzt sind, bleiben RGB- und UV-Dilatation beim Referenzwert von 2 px.
Der Test untersucht daher Topologie, Artefaktlage und Laufzeit, nicht die
Maskendilatation. Er verändert gleichzeitig den Coarse-Zielzähler von 15.000
auf 12.000, das Meshziel von 1.000.000 auf 50.000 und das Refinement von 7.000
auf 2.000 Updates; mit `SURFACE_SAMPLE_COUNT=2000000` verändert er zusätzlich
die Oberflächenabtastung. Würden zusätzlich die Dilatationen auf null gesetzt,
änderten sich gleichzeitig Coarse-Zähler, Stichprobenzahl, Vertexzahl,
Refinement und Maskenrand; daraus ließe sich keine belastbare Einzelursache
ableiten.

## 6.1 Empfohlene Priorisierung bei drei Tagen

1. Zuerst eine oder zwei Checkpoint-Ablationen mit nur einer geänderten
  Extraktionsvariable ausführen und das Coarse-Mesh in denselben Ansichten
  prüfen. Beginne mit `depth10_v50000`, danach `depth8_v50000`; nutze die
  reduzierte Stichprobenvariante nur bei Zeitdruck und kennzeichne sie als
  Screening.
2. Wenn keine schnelle Extraktionsvariante die Flächen plausibel reduziert,
  den ansonsten referenzgleichen Coarse-only-Null-RGB-Dilatationslauf starten.
  Er liefert die saubere Aussage zur 2-px-RGB-Dilatation an der ersten
  Artefaktstufe und spart Refinement sowie UV-Baking.
3. Den kombinierten 12k/50k/short-Screening-Lauf nur verwenden, wenn eine
  schnelle Funktions- und Laufzeitprüfung nötig ist. Er ersetzt weder die
  Checkpoint-Ablation noch den kontrollierten Null-Dilatationsvergleich.
4. Nach jedem Test zuerst das Coarse-Mesh prüfen. Nur wenn die Fläche dort
  verschwindet oder klar kleiner wird, sind Refinement und OBJ als Folgeprodukt
  erneut relevant.

## 6.2 Ergebnis des schnellen Null-Dilatations-Screenings

Der Lauf
`masked_7000_dn_consistency_no_dilation_screen_c12000_v100000_s5m` wurde mit
Zielzähler 12.000, 100.000 Mesh-Vertices, fünf Millionen Zielstichproben,
mittlerem Refinement sowie null Pixel RGB- und UV-Dilatation in ungefähr einer
Stunde vollständig abgeschlossen. Das neue Coarse-Mesh wirkt visuell kompakter
und enthält deutlich weniger Ausreißer als die vorher betrachtete
`depth8_v50000`-Ablation; Restflächen bleiben jedoch vorhanden. Auch die
verfeinerte Gaussian-PLY zeigt sichtbar weniger großflächige Ausstrahlungen.
Diese Beobachtung ist vielversprechend, aber wegen der gleichzeitig geänderten
Parameter noch kein kausaler Nachweis für die Maskendilatation.

Der nächste Test ist deshalb ein Coarse-only-Kontrolllauf mit identischen
12.000/100.000/5-Millionen-Einstellungen und wiederhergestellter
2-px-RGB-Dilatation. UV-Dilatation und Refinement sind für diesen Coarse-Vergleich
wirkungslos und werden durch den Early Exit nicht erreicht:

```bash
SUGAR_RUN_TAG=masked_7000_dn_consistency_dilation2_control_c12000_v100000_s5m \
COARSE_ITERATIONS=12000 \
MESH_VERTICES=100000 \
SURFACE_SAMPLE_COUNT=5000000 \
MASK_DILATION_PX=2 \
STOP_AFTER_COARSE_MESH=1 \
RUN_CONSENSUS_CROP=0 \
./run_masked_sugar.sh
```

Das vorhandene Null-Dilatations-Coarse-Mesh ist in der direkten visuellen
Gegenüberstellung klar besser als dieser Kontrolllauf. Der Kontrolllauf zeigt
bei identischem Zielzähler, identischer Extraktion und identischer DN-Maske
wieder deutlich größere Restflächen. Damit ist ein wesentlicher Beitrag der
2-px-RGB-Randdilatation stark gestützt. Die verbleibenden Artefakte des
Null-Dilatationslaufs zeigen zugleich, dass sie nicht als einzige Ursache
bezeichnet werden darf.

## 6.3 Einmal erodierte RGB-Maske

Der nächste Lauf prüft, ob auch der undilatierte Rand der ursprünglichen
`default`-Maske noch unsichere Pixel enthält. `middle` entsteht durch genau
einen OpenCV-Erosionsdurchlauf mit einem $5\times5$-Kernel. Das entspricht
ungefähr zwei Pixeln Randabtrag pro Seite und nicht einer 1-px-Erosion. Über die
699 vorhandenen Masken behält `middle` im Mittel 78,9 % und im Median 80,7 % der
Vordergrundfläche; keine Maske wird leer, der minimale Einzelwert beträgt aber
42,0 %. `small` behält im Mittel nur 60,6 % und wird deshalb zunächst nicht
verwendet.

Der vollständige Lauf hält die erfolgreiche schnelle Konfiguration fest:

```bash
SUGAR_RUN_TAG=masked_7000_dn_consistency_middle_no_dilation_c12000_v100000_s5m \
COARSE_ITERATIONS=12000 \
MESH_VERTICES=100000 \
SURFACE_SAMPLE_COUNT=5000000 \
MASK_LEVEL=middle \
MASK_DILATION_PX=0 \
NORMAL_MASK_LEVEL=middle \
TEXTURE_MASK_LEVEL=middle \
TEXTURE_MASK_DILATION_PX=0 \
REFINEMENT_TIME=medium \
STOP_AFTER_COARSE_MESH=0 \
RUN_CONSENSUS_CROP=0 \
./run_masked_sugar.sh
```

Gegenüber dem abgeschlossenen vollständigen Null-Dilatationslauf ändert sich im
Coarse-Training und Refinement nur die RGB-Maskenstufe von `default` auf
`middle`. Die DN-Maske war bereits `middle` und bleibt unverändert. Die
Umstellung der UV-Maske auf `middle` verändert nur die Texturbelegung, nicht die
Geometrie. Bewertet wird zuerst das Coarse-Mesh: Weniger Restflächen bei
vollständig erhaltenen Bügeln sprechen für die Erosion; fehlende oder sichtbar
verkürzte dünne Teile zeigen eine zu starke Erosion an.

Die verfeinerte PLY dieses Screenings ist eine Gaussian-Splat-PLY mit 98.281
Gaussian-Einträgen und keiner Mesh-Face-Liste; sie ist nicht als gewöhnliches
CloudCompare-Mesh zu interpretieren. Das texturierte OBJ enthält 52.385
geometrische Vertices, 98.281 gültige Dreiecke und konsistente UV-Indizes. Sein
ursprünglicher Windows-UNC-Pfad ist exakt 260 Zeichen lang. Eine importerfreundliche
Kopie mit kurzen Namen liegt unter
`data/06_mesh/no_dilation_screen_import/{mesh.obj,mesh.mtl,texture.png}`. Der
SuGaR-Exporter wurde zusätzlich so korrigiert, dass zukünftige OBJ-Dateien mit
einem abschließenden Zeilenumbruch geschrieben werden.

## 6.4 Gemischtes Ergebnis der `middle`-Ablation und Produktentscheidung

Die visuelle Gegenüberstellung des vollständigen `middle`-Laufs mit dem
vergleichbaren `default`-Lauf bei null RGB-Dilatation ergibt keinen eindeutigen
Sieger. `middle` reduziert die weit von der Sonnenbrille entfernten und damit
offensichtlichsten Restflächen. Gleichzeitig werden die Objektgrenzen etwas
zackiger, es entstehen zusätzliche lokale Randartefakte und in einzelnen
Gläsern kleine Löcher. `default + 0 px` bewahrt die Rand- und Glasgeometrie
besser, enthält aber mehr abgelöste Flächen im Umfeld.

Die Interpretation ist ein diskreter Gaussian-Inklusionskonflikt. Die Maske
gewichtet Pixel, der Gaussian wird jedoch als zusammenhängende Primitive mit
räumlicher Ausdehnung optimiert. Liegt sein projizierter Support teilweise
innerhalb und teilweise außerhalb der erodierten Maske, wird er nicht anteilig
geteilt. Die Erosion kann dadurch unsichere Hintergrundsupervision reduzieren,
aber zugleich echte Randstützen entfernen oder die lokale Oberflächenbildung
instabil machen. Die beobachteten zackigen Grenzen und einzelnen Glaslöcher
sind damit vereinbar. Die Ursache ist damit nicht vollständig auf die Maske
reduziert: Coarse-Regularisierung, Poisson-Rekonstruktion,
Dichtebereinigung und das an das Coarse-Mesh gebundene Refinement bleiben
weitere mögliche Einflussgrößen.

Für die Projekt- und Bachelorarbeit ist dieser Zielkonflikt anders zu bewerten
als bei einer Arbeit zur metrologisch vollständigen Rekonstruktion eines
Einzelobjekts. Das Ziel ist ein korrekt vermessenes, georeferenziertes und wie
eine bereinigte Punktwolke nutzbares Produkt. Eine geometrische Änderung durch
Postprocessing ist deshalb zulässig, wenn sie als eigener, reproduzierbarer
Bereinigungsschritt ausgewiesen und im georeferenzierten Raum validiert wird.
Für den angesetzten Toleranzrahmen von etwa +/- 10 cm zählen die Lage der
relevanten Objektteile, die Vollständigkeit der Nutzgeometrie und die Entfernung
größerer Ausreißer; ein optisch glatterer Rand allein ist kein Genauigkeitsnachweis.

### Vorläufige Entscheidung

Als Basis für ein mögliches Endprodukt wird zunächst `default + 0 px`
bevorzugt. Die erhaltene Rand- und Glasgeometrie ist wichtiger als eine
aggressive Artefaktentfernung, weil fehlende Randbereiche und Löcher durch
späteres Mesh-Cleaning nicht zuverlässig zurückgewonnen werden können. Die
entfernten Flächen im Umfeld sind dagegen grundsätzlich gezielter als
eigenständige, nicht zum Objekt gehörende Komponenten oder als semantisch nicht
unterstützte Flächen prüfbar. `middle + 0 px` bleibt eine gleichwertig zu
dokumentierende Vergleichsvariante und kann als Endprodukt gewählt werden,
wenn die entfernten Ausreißer die spätere Messaufgabe stärker beeinträchtigen
als die Randverluste.

Mehr Refinement-Iterationen sind dafür nicht automatisch die beste nächste
Maßnahme. Das Refinement ist an das Coarse-Mesh gebunden; es kann vorhandene
Löcher, zackige Grenzen oder Restflächen erhalten beziehungsweise verstärken,
aber fehlende Bild- oder Geometrieevidenz nicht zuverlässig ersetzen. Ein
kontrollierter Mesh-Bereinigungsschritt ist daher zunächst zielgerichteter als
ein weiterer ungerichteter Trainingslauf.

### Kontrollierter Postprocessing-Test

Der lokale SuGaR-Pfad enthält bereits ein optionales `postprocess_mesh`. Es
entfernt iterativ schwach dichte Randdreiecke anhand der Mesh-Konnektivität und
nimmt anschließend ausgewählte Dreiecke mit ausreichender Dichte wieder auf.
Die bisherigen Läufe haben diese Option nicht aktiviert. Sie soll nicht blind
mit den Standardwerten eingesetzt werden, weil sie ebenfalls relevante dünne
Strukturen oder Glasflächen entfernen kann.

Der Test wird deshalb mit getrennten Ausgaben durchgeführt:

1. unverändertes `default + 0 px` als geometrische Referenz,
2. konservatives SuGaR-Postprocessing mit wenigen Iterationen,
3. unverändertes `middle + 0 px` als maskenbasierte Vergleichsvariante.

Für jede Variante werden dieselben Ansichten und dieselbe georeferenzierte
Auswertung verwendet. Zu protokollieren sind die Reduktion eindeutig
abgelöster Flächen, die Erhaltung von Bügeln und Glasrändern, die Anzahl und
Lage von Glaslöchern sowie Abweichungen der verfügbaren Referenzpunkte. Das
Rohmesh bleibt unverändert archiviert; nur die abgeleitete Bereinigung wird als
Produktmesh verwendet. Die Entscheidung für das Endprodukt erfolgt erst,
wenn die visuelle Verbesserung nicht mit einer Überschreitung des
projektbezogenen +/- 10-cm-Toleranzrahmens oder dem Verlust relevanter
Geometrie erkauft wird.

## 6.5 Iterations- und Opazitätsbefund

Eine zusätzliche Serie hält `default + 0 px` für RGB, `middle` für DN,
fünf Millionen Oberflächenstichproben, 200.000 Zielvertices, mittleres
Refinement und deaktivierten Crop konstant. Verglichen werden ausschließlich
die Coarse-Zielzähler `9001`, `10000` und `18000`.

Qualitativ zeigt `c18000` geschlossenere, konsistentere Brillenbügel als
`c9001` und `c10000`. Die Restflächen verschwinden nicht vollständig, treten
aber an weitgehend denselben Kontakt- beziehungsweise Ansatzbereichen zwischen
Brille und Untergrund auf. Bei der langen Optimierung werden sie räumlich
konstanter. Das ist ein Hinweis auf eine systematische Mehransichts- oder
Oberflächenmehrdeutigkeit, nicht auf zufällige einzelne Input-Ausreißer.

Die Checkpoint-Auswertung macht den Zeitplan explizit:

| Coarse-Ziel | Gaussians im Checkpoint | Gaussians mit $\alpha>0{,}5$ | Coarse-Mesh: Vertices / Dreiecke |
| --- | ---: | ---: | ---: |
| `9001` | 2.363 | 2.363 | 98.891 / 190.988 |
| `10000` | 2.368 | 2.368 | 101.242 / 192.670 |
| `18000` | 2.368 | 1.358 | 101.559 / 195.771 |

Der Coarse-Trainer startet bei `6999` und führt bei `9001` vor dem Bildverlust
eine harte Bereinigung mit $\alpha<0{,}5$ aus. Der Lauf `9001` enthält daher
nur einen einzigen DN-/SDF-Update-Schritt; `10000` enthält ungefähr 1.000 und
`18000` ungefähr 9.000 Updates nach der Aktivierung. Im Extractor wird vor der
Oberflächenabtastung erneut die feste Schwelle $\alpha>0{,}5$ verwendet. Im
`c18000`-Checkpoint werden dadurch 1.010 der noch vorhandenen 2.368 Gaussians
nicht für die Surface-Samples und Poisson verwendet.

Die bessere Bügelgeometrie von `c18000` folgt damit nicht einfach aus mehr
starken Oberflächenstützen. Plausibler ist, dass die längere DN-/SDF-Phase
Position, Skala, Orientierung und Dichte der erhaltenen Stützen konsistenter
ausrichtet. Gleichzeitig können wiederkehrende Kontaktbereiche stabilisiert
werden. Die Opazitätsdiagnose der gefilterten 6.175 STS-Gaussians zeigte keine
frei abgelösten Input-Ausreißer. Sie schließt aber räumlich ausgedehnte
Gaussians, unvollständige Vordergrund-Hintergrund-Trennung, unsichere Normalen
oder Poisson-Flächenschluss als gemeinsame Ursache nicht aus.

### Nächste trennscharfe Abklärung

Der vorhandene `c18000`-Coarse-Checkpoint soll ohne neues Training mit
unveränderten 5 Millionen Surface-Samples, Poisson-Tiefe, Dichtequantil,
Projektion und Vertexziel erneut extrahiert werden. Dabei wird nur die
Extractor-Schwelle verglichen:

1. Referenz: $\alpha>0{,}5$.
2. Extremtest: $\alpha>0$, also alle 2.368 im Checkpoint vorhandenen
  Gaussians.

Verbessern sich reale Bügelbereiche und Lücken ohne neue Flächen, waren die
niedrig opaken Stützen relevant. Bleiben die Kontaktflächen ortsstabil, liegt
die Ursache wahrscheinlicher vor oder innerhalb der Poisson-Rekonstruktion.
Erst nach diesem Extract-only-Vergleich ist eine vollständige Coarse-Ablation
mit geänderter Opazitätsbereinigung begründet.

## 7. Multi-View-Crop und metrische Bewertung

Der konservative Crop ist für das dichte Brillenmesh zu schwach, während
`semantic-core` zu viel Geometrie entfernt. Beide Varianten bleiben
diagnostische Nebenprodukte und werden nicht zur Behebung der Coarse-Artefakte
eingesetzt.

Die visuelle Artefaktanalyse ersetzt keine metrische Bewertung. Eine spätere
Centerline- und GNSS-Referenzprüfung mit RMSE und Hausdorff-Distanz bleibt der
Nachweis für die geodätische Verwendbarkeit der Pipeline.