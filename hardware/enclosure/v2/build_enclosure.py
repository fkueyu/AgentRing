import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

DEST = Path(__file__).resolve().parent
OPEN_CENTER = "--open-center" in sys.argv
PCB_RADIUS = 32.0
PCB_BOTTOM = 6.10
PCB_TOP = 7.70
LED_TOP = 9.40
OUTER_RADIUS = 35.80
TOP = 15.42
SEGMENTS = 192

original_scene = bpy.context.scene
scene = bpy.data.scenes.new("Enclosure")
bpy.context.window.scene = scene
if original_scene.name == "Scene" and set(obj.name for obj in original_scene.objects) <= {"Cube", "Camera", "Light"}:
    bpy.data.scenes.remove(original_scene)
scene.name = "01 · Enclosure"
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 0.001
scene.unit_settings.length_unit = "MILLIMETERS"


def collection(parent, name):
    layer = bpy.data.collections.new(name)
    parent.children.link(layer)
    return layer


parts = collection(scene.collection, "01 · Enclosure parts")
reference = collection(scene.collection, "02 · PCB reference")
details = collection(reference, "Components")


def material(name, color, metallic=0, roughness=0.45, emission=0, subsurface=0):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1)
    result.use_nodes = True
    shader = next(n for n in result.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Subsurface Weight"].default_value = subsurface
    if emission:
        shader.inputs["Emission Color"].default_value = (*color, 1)
        shader.inputs["Emission Strength"].default_value = emission
    return result


shell = material("Graphite · matte polymer", (0.045, 0.055, 0.069), roughness=0.32)
opal = material("Opal · diffuser", (0.82, 0.89, 0.93), roughness=0.28, subsurface=0.12)
black_pcb = material("PCB · black solder mask", (0.016, 0.023, 0.027), roughness=0.37)
silver = material("USB & switches · nickel", (0.44, 0.49, 0.55), 0.82, 0.26)
chip_case = material("Components · epoxy", (0.017, 0.019, 0.024), roughness=0.44)
ceramic = material("LED · ceramic package", (0.66, 0.69, 0.68), roughness=0.30)
lens = material("LED · lens", (0.90, 0.80, 0.55), roughness=0.30)
copper = material("Pads · plated brass", (0.58, 0.34, 0.11), 0.75, 0.30)


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def normals(obj):
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()


def lathe(name, profile, layer, mat=None, adjust=None):
    vertices = []
    for index, (radius, height) in enumerate(profile):
        for segment in range(SEGMENTS):
            azimuth = segment * math.tau / SEGMENTS
            r = adjust(index, azimuth, radius) if adjust else radius
            vertices.append((r * math.cos(azimuth), r * math.sin(azimuth), height))
    faces = []
    for row in range(len(profile) - 1):
        for segment in range(SEGMENTS):
            next_segment = (segment + 1) % SEGMENTS
            faces.append((
                row * SEGMENTS + segment, row * SEGMENTS + next_segment,
                (row + 1) * SEGMENTS + next_segment, (row + 1) * SEGMENTS + segment,
            ))
    if profile[0] == profile[-1]:
        vertices = vertices[:-SEGMENTS]
        last_start = len(vertices) - SEGMENTS
        for segment in range(SEGMENTS):
            next_segment = (segment + 1) % SEGMENTS
            faces[last_start + segment] = (
                last_start + segment, last_start + next_segment, next_segment, segment,
            )
    else:
        faces.append(tuple(reversed(range(SEGMENTS))))
        faces.append(tuple(range(len(vertices) - SEGMENTS, len(vertices))))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    layer.objects.link(obj)
    normals(obj)
    for face in mesh.polygons:
        face.use_smooth = abs(face.normal.z) < 0.98
    if mat:
        mesh.materials.append(mat)
    return obj


def primitive_move(obj, name, layer, mat=None):
    obj.name = name
    for existing_layer in tuple(obj.users_collection):
        existing_layer.objects.unlink(obj)
    layer.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    return obj


def bevel(obj, width, segments=3, apply=False):
    modifier = obj.modifiers.new("Rounded edges", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    modifier.harden_normals = True
    if apply:
        activate(obj)
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def box(name, loc, size, layer, mat=None, radius=0, rotate=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = primitive_move(bpy.context.object, name, layer, mat)
    obj.dimensions = size
    obj.rotation_euler.z = rotate
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if radius:
        bevel(obj, radius, apply=True)
    return obj


def cylinder(name, loc, radius, depth, layer, mat=None, segments=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius, depth=depth, location=loc)
    return primitive_move(bpy.context.object, name, layer, mat)


def radial_box(name, azimuth, radius, z, size, layer, mat=None, rounding=0):
    direction = math.radians(azimuth)
    center = (radius * math.cos(direction), radius * math.sin(direction), z)
    return box(name, center, size, layer, mat, rounding, direction)


def boolean(target, tool, operation="DIFFERENCE"):
    activate(target)
    modifier = target.modifiers.new(tool.name, "BOOLEAN")
    modifier.operation = operation
    modifier.solver = "EXACT"
    modifier.object = tool
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(tool, do_unlink=True)


def bump_profile(angle, peaks):
    def influence(peak):
        distance = abs((math.degrees(angle) - peak + 180) % 360 - 180)
        return max(0, 1 - distance / 5.8)
    return max(influence(peak) for peak in peaks)


def pcb_opening(name, z, depth, layer):
    # Traced from the LED face, with the perpendicular USB-C edge on +X.
    radius = 22.1
    edge_x = 5.95
    endpoint_angle = math.acos(edge_x / radius)
    curve = []
    for step in range(109):
        angle = endpoint_angle + (math.tau - 2 * endpoint_angle) * step / 108
        curve.append((radius * math.cos(angle), radius * math.sin(angle)))
    curve += [(6.1, -13.0), (-1.3, -13.0), (-1.75, -12.55),
              (-1.75, 12.55), (-1.3, 13.0), (5.95, 13.0)]
    n = len(curve)
    vertices = [(x, y, height) for height in (z - depth / 2, z + depth / 2) for x, y in curve]
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, j + n, i + n))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    layer.objects.link(obj)
    normals(obj)
    return obj


def shape_engravings(target, layer):
    for label, x, y in [("RST", 11.65, 15.25), ("BOOT", 16.25, 15.25)]:
        curve = bpy.data.curves.new(label, "FONT")
        curve.body = label
        curve.align_x = "CENTER"
        curve.align_y = "CENTER"
        curve.size = 1.28
        curve.extrude = 0.24
        obj = bpy.data.objects.new(label, curve)
        obj.location = (x, y, 15.42)
        layer.objects.link(obj)
        activate(obj)
        bpy.ops.object.convert(target="MESH")
        boolean(target, obj)


base = lathe("A · Base", [
    (35.04, 0), (35.45, 0.16), (35.72, 0.46), (35.80, 0.83),
    (35.80, 10.28), (35.68, 10.62), (35.46, 10.80),
    (34.24, 10.80), (34.15, 10.66), (34.15, 8.56),
    (33.99, 8.25), (32.41, 7.91), (32.38, 6.23),
    (32.30, PCB_BOTTOM), (30.64, PCB_BOTTOM), (30.45, 5.92),
    (30.45, 2.12), (30.18, 1.80),
], parts, shell)
# A constant octagonal section keeps the four 45-degree corner flats through the wall.
port_half_width = 6.0
port_half_height = 4.1
port_z = 4.94
corner = 1.0
w, h = port_half_width, port_half_height
section = [(-w+corner,-h), (w-corner,-h), (w,-h+corner), (w,h-corner),
           (w-corner,h), (-w+corner,h), (-w,h-corner), (-w,-h+corner)]
points = [(x,y,port_z+z) for x in (29.6,42.0) for y,z in section]
faces = [tuple(reversed(range(8))),tuple(range(8,16))]
for i in range(8):
    j = (i+1)%8
    faces.append((i,j,8+j,8+i))
port_mesh = bpy.data.meshes.new("Chamfered USB-C aperture")
port_mesh.from_pydata(points, [], faces)
usb_cut = bpy.data.objects.new("USB-C opening",port_mesh)
parts.objects.link(usb_cut)
normals(usb_cut)
boolean(base, usb_cut)

# Stops rise from the floor below the solder tabs and behind the mating face.
# 9.14 mm estimated shell width + 0.40 mm each side gives a 9.94 mm channel.
for side in (-1, 1):
    stop = box("USB-C anti-rotation stop", (27.60, side*5.97, 3.12),
               (3.60, 2.00, 3.36), parts, radius=0.25)
    boolean(base, stop, "UNION")
usb_key = radial_box("Alignment-key slot", 207, 34.28, 9.96, (1.43, 3.15, 2.20), parts, rounding=0.12)
boolean(base, usb_key)
pry = radial_box("Cover release notch", 318, 35.55, 10.73, (2.9, 5.1, 1.26), parts, rounding=0.37)
boolean(base, pry)
def diffuser_fit(index, angle, radius):
    if index in (2, 3):
        return radius + 0.31 * bump_profile(angle, (53, 153, 262))
    return radius


diffuser = lathe("B · Opal diffuser", [
    (32.56, 8.88), (33.60, 8.88), (33.91, 9.20), (33.93, 10.41),
    (34.04, 10.83), (35.43, 10.83), (35.69, 11.02), (35.80, 11.28),
    (35.80, 14.08), (35.61, 14.59), (35.23, 15.05), (34.72, 15.31),
    (34.20, 15.40), (24.35, 15.40), (24.07, 15.19), (24.07, 14.46),
    (23.32, 14.46), (23.26, 14.34), (23.26, 13.81), (23.49, 13.58),
    (24.12, 13.51), (32.37, 13.51), (32.55, 13.34), (32.56, 8.88),
], parts, opal, diffuser_fit)
for angle in (72.5, 159.5, 260.5):
    stop = radial_box("PCB retaining pad", angle, 32.42, 9.51, (2.08, 1.40, 2.98), parts, rounding=0.11)
    boolean(diffuser, stop, "UNION")
key = radial_box("Base alignment key", 207, 34.25, 10.0, (1.03, 2.46, 1.60), parts, rounding=0.10)
boolean(diffuser, key, "UNION")
cap_slot = radial_box("Cap alignment-key slot", 216, 23.10, 13.83, (0.98, 2.40, 1.48), parts, rounding=0.10)
boolean(diffuser, cap_slot)


def cap_fit(index, angle, radius):
    if index in (2, 3):
        return radius + 0.30 * bump_profile(angle, (20, 125, 265))
    return radius


cap = lathe("C · Center cover", [
    (22.69, 13.02), (23.01, 13.30), (23.03, 13.79), (23.03, 14.22),
    (23.02, 14.49), (23.72, 14.49), (23.83, 14.61), (23.83, 15.20),
    (23.59, TOP),
], parts, shell, cap_fit)
cap_key = radial_box("Diffuser alignment key", 216, 23.13, 13.87, (0.58, 1.93, 1.02), parts, rounding=0.08)
boolean(cap, cap_key, "UNION")

for label, x, y in [("RST", 11.65, 12.15), ("BOOT", 16.25, 12.28)]:
    hole = cylinder(label + " access hole", (x, y, 14.30), 1.10, 3.55, parts)
    boolean(cap, hole)
shape_engravings(cap, parts)

if OPEN_CENTER:
    boolean(cap, pcb_opening("Center aperture", 14.3, 5.0, parts))
    boolean(base, pcb_opening("Center aperture", 0.7, 3.5, parts))

board = lathe("PCB · Ø64 mm reference", [
    (PCB_RADIUS, PCB_BOTTOM), (PCB_RADIUS, PCB_TOP),
], reference, black_pcb)
boolean(board, pcb_opening("PCB cutout", 7, 4, reference))
for i in range(4):
    y = -9.65 - 2.54 * i
    hole = cylinder("Header bore", (11.65, y, 6.9), 0.61, 3.0, reference, segments=28)
    boolean(board, hole)
    pad = cylinder("Header pad", (11.65, y, PCB_TOP + 0.02), 0.86, 0.04, details, copper, 28)
    hole = cylinder("Pad bore", (11.65, y, PCB_TOP), 0.62, 0.5, details, segments=28)
    boolean(pad, hole)

led_positions = [(1550, 718), (1530, 586), (1464, 465), (1370, 361),
                 (1260, 288), (1136, 241), (1013, 240), (886, 259),
                 (768, 307), (668, 392), (590, 496), (548, 620),
                 (536, 744), (555, 871), (601, 987), (679, 1096),
                 (785, 1164), (902, 1221), (1036, 1240), (1167, 1223),
                 (1292, 1170), (1402, 1090), (1487, 978), (1534, 852)]
for i, (px, py) in enumerate(led_positions, 1):
    angle = math.degrees(math.atan2(738 - py, px - 1050))
    radial_box(f"LED {i:02d} · package", angle, 28.55, 8.53, (5.0, 5.0, 1.64), details, ceramic, 0.24)
    theta = math.radians(angle)
    led_lens = cylinder(f"LED {i:02d} · lens",
                        (28.55 * math.cos(theta), 28.55 * math.sin(theta), 9.37),
                        1.72, 0.06, details, lens, 36)
    bevel(led_lens, 0.02)

for name, x, y in [("RST", 11.65, 12.15), ("BOOT", 16.25, 12.28)]:
    box(name + " · switch", (x, y, 8.35), (3.40, 4.35, 1.30), details, silver, 0.20)
    button = cylinder(name + " · top", (x, y, 9.12), 1.11, 0.34, details, ceramic)
    bevel(button, 0.13)

box("ESP32-C3", (16.15, -0.3, 8.13), (5.70, 5.70, 0.82), details, chip_case, 0.15, math.radians(45))
box("Crystal", (14.6, 6.3, 8.15), (3.5, 2.7, 0.86), details, silver, 0.14, math.radians(41))
usb = box("USB-C · port", (29.15, 0, 4.50), (8.60, 9.14, 3.20), details, silver, 0.58)
socket = box("USB-C · internal cavity", (32.75, 0, 4.50), (3.10, 7.42, 2.35), details, radius=0.40)
boolean(usb, socket)
box("USB-C · tongue", (32.10, 0, 4.50), (2.06, 6.2, 0.46), details, chip_case, 0.12)

base["PCB diameter (mm)"] = 64.0
base["PCB bore at seat (mm)"] = 64.60
base["Outer diameter (mm)"] = 71.60
base["USB-C opening (mm)"] = "12.0 W × 8.2 H, C1.0"
base["PCB seat Z (mm)"] = PCB_BOTTOM
diffuser["Air gap above LED (mm)"] = round(13.51 - LED_TOP, 2)
diffuser["PCB retaining pads"] = "72.5°, 159.5°, 260.5° from the USB-C axis"
cap["Access bores (mm)"] = 2.20
cap["Aperture"] = "Preserved" if OPEN_CENTER else "Covered"
board["PCB thickness measured (mm)"] = 1.60
board["LED top to USB-C bottom measured (mm)"] = 6.50
board["LED height above PCB assumed (mm)"] = LED_TOP - PCB_TOP
board["USB-C height estimated (mm)"] = 3.20
scene["Revision"] = "V2 · USB-C aperture and anti-rotation stops"
scene["Assembled dimensions (mm)"] = "71.60 × 71.60 × 15.42"

for part in (base, diffuser, cap):
    check = bmesh.new()
    check.from_mesh(part.data)
    assert all(edge.is_manifold for edge in check.edges), part.name
    assert check.calc_volume(signed=True) > 0, part.name
    assert min(face.calc_area() for face in check.faces) > 1e-9, part.name
    print(f"PART {part.name}: {len(check.verts)} vertices, volume {check.calc_volume():.1f} mm³")
    check.free()

notes = bpy.data.texts.new("Dimensions & assembly")
notes.write(f"""AGENTRING / ENCLOSURE V2

Nominal assembly: Ø71.60 × 15.42 mm.
Measured PCB: Ø64.00 mm, 1.60 mm board thickness.
Measured envelope: 6.50 mm from LED face to bottom of USB-C shell.
LED and USB-C projection estimated separately as 1.70 and 3.20 mm.
The housing includes Ø64.60 mm clearance at the PCB seat, an opal diffuser and Ø2.20 mm BOOT/RST openings.
The shell opening for the USB-C cable is 12.0 × 8.2 mm with 1.0 mm corner chamfers and a 9.94 mm guide channel.
The center is {"open" if OPEN_CENTER else "closed"} in this revision.

Install the PCB connector first, with the LED side up. Align the diffuser and
center cover with their offset keys. The three small diffuser pads retain the
PCB between the LEDs. Their clearance and the two friction fits need a
physical fit check before committing to a finished print.
Use the seam notch to release the diffuser.

01 · Enclosure: mm-scale assembly and PCB reference.
02 · Preview: assembled and exploded views for presentation.
PCB and components are reference geometry.
""")


# Reuse design meshes for a second scene with assembled and exploded presentation views.
preview = bpy.data.scenes.new("02 · Preview")
preview.unit_settings.system = "METRIC"
preview.unit_settings.scale_length = 0.001
preview.unit_settings.length_unit = "MILLIMETERS"
assembled = collection(preview.collection, "Assembled")
exploded = collection(preview.collection, "Exploded")
studio = collection(preview.collection, "Studio")


def duplicate(obj, layer, offset, color=None):
    copy = obj.copy()
    copy.data = obj.data
    layer.objects.link(copy)
    copy.location += Vector(offset)
    if color:
        copy.material_slots[0].link = "OBJECT"
        copy.material_slots[0].material = color
    return copy


# Pale blue emitter with subtle radial color differences around the ring.
lit_opal = material("Preview · lit opal", (0.16, 0.52, 0.80), roughness=0.29, emission=1.1)
nodes = lit_opal.node_tree.nodes
links = lit_opal.node_tree.links
tex = nodes.new("ShaderNodeTexCoord")
xyz = nodes.new("ShaderNodeSeparateXYZ")
links.new(tex.outputs["Generated"], xyz.inputs[0])
ramp = nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.02
ramp.color_ramp.elements[0].color = (0.15, 0.25, 0.78, 1)
ramp.color_ramp.elements[1].position = 0.98
ramp.color_ramp.elements[1].color = (0.025, 0.71, 0.87, 1)
links.new(xyz.outputs["X"], ramp.inputs[0])
lit_shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
links.new(ramp.outputs[0], lit_shader.inputs["Base Color"])
links.new(ramp.outputs[0], lit_shader.inputs["Emission Color"])

for obj in (base, diffuser, cap):
    duplicate(obj, assembled, (43, -7, 0.15), lit_opal if obj == diffuser else None)

for obj, z in [(base, 0.15), (diffuser, 36), (cap, 58)]:
    duplicate(obj, exploded, (-40, 8, z))
for obj in reference.all_objects:
    duplicate(obj, exploded, (-40, 8, 20))

# Preview the production geometry with a subdued studio floor.
floor_mat = material("Studio · slate", (0.076, 0.097, 0.118), roughness=0.72)
box("Stage", (0, 0, -1.05), (650, 650, 2), studio, floor_mat)

def point_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


camera_data = bpy.data.cameras.new("Camera")
camera = bpy.data.objects.new("Camera", camera_data)
studio.objects.link(camera)
camera.location = (77, -196, 142)
point_at(camera, (0, 0, 28))
camera_data.type = "ORTHO"
camera_data.ortho_scale = 185
camera_data.clip_end = 1500
preview.camera = camera

for name, pos, power, size, color in [
    ("Key light", (30, -69, 150), 540000, 108, (0.86, 0.93, 1.0)),
    ("Fill light", (-112, -60, 85), 260000, 85, (0.83, 0.88, 1.0)),
    ("Rim light", (45, 99, 96), 475000, 78, (1.0, 0.85, 0.68)),
]:
    light = bpy.data.lights.new(name, "AREA")
    light.energy = power
    light.shape = "DISK"
    light.size = size
    light.color = color
    obj = bpy.data.objects.new(name, light)
    studio.objects.link(obj)
    obj.location = pos
    point_at(obj, (0, 0, 15))

preview.world = bpy.data.worlds.new("Studio sky")
preview.world.use_nodes = True
next(n for n in preview.world.node_tree.nodes if n.type == "BACKGROUND").inputs["Color"].default_value = (0.32, 0.38, 0.48, 1)
next(n for n in preview.world.node_tree.nodes if n.type == "BACKGROUND").inputs["Strength"].default_value = 0.28
preview.render.engine = "CYCLES"
preview.cycles.samples = 24
preview.cycles.use_denoising = True
preview.render.resolution_x = 1500
preview.render.resolution_y = 1060
preview.render.resolution_percentage = 100
preview.render.image_settings.file_format = "PNG"
preview.render.filepath = "//AgentRing_Enclosure_Preview.png"
preview.view_settings.view_transform = "AgX"
preview.view_settings.look = "AgX - Medium High Contrast"

bpy.context.window.scene = scene
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = None
for area in bpy.context.screen.areas:
    if area.type == "VIEW_3D":
        area.spaces.active.shading.color_type = "MATERIAL"
        area.spaces.active.region_3d.view_location = (0, 0, 8.0)
        area.spaces.active.region_3d.view_distance = 123
        area.spaces.active.region_3d.view_rotation = Euler((math.radians(58), 0, math.radians(25)), "XYZ").to_quaternion()
        area.spaces.active.region_3d.view_perspective = "ORTHO"
        area.spaces.active.overlay.show_floor = False
        area.spaces.active.overlay.show_axis_x = False
        area.spaces.active.overlay.show_axis_y = False
        area.spaces.active.clip_end = 2500

DEST.mkdir(exist_ok=True, parents=True)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST / "AgentRing_Enclosure_V2.blend"), compress=True)

# Export each shell on its own print bed. Both visible upper faces face down.
import struct
from collections import Counter
for part, filename, invert in [(base, "01_Base_V2", False), (diffuser, "02_Diffuser", True), (cap, "03_Center", True)]:
    mesh = part.data
    mesh.calc_loop_triangles()
    bed = max(v.co.z for v in mesh.vertices) if invert else min(v.co.z for v in mesh.vertices)
    def bed_point(i):
        x, y, z = mesh.vertices[i].co
        return Vector((x, -y, bed-z)) if invert else Vector((x, y, z-bed))
    edges = Counter()
    volume = 0.0
    with (DEST / (filename + ".stl")).open("wb") as out:
        out.write(bytes(80) + struct.pack("<I", len(mesh.loop_triangles)))
        for tri in mesh.loop_triangles:
            a,b,c = [bed_point(i) for i in tri.vertices]
            normal = (b-a).cross(c-a)
            assert normal.length > 1e-8, filename
            volume += a.dot(b.cross(c))/6
            for u,v in [(a,b),(b,c),(c,a)]:
                edges[tuple(sorted((tuple(u),tuple(v))))] += 1
            out.write(struct.pack("<12fH", *normal.normalized(), *a, *b, *c, 0))
    assert volume > 0 and set(edges.values()) == {2}, filename
    print("STL verified", filename, round(volume, 1))
if "--render" in sys.argv:
    bpy.ops.render.render(write_still=True, scene=preview.name)
