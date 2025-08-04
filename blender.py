import bpy
import json
import math
import mathutils

D = bpy.data
C = bpy.context
scene = C.scene
obj = C.object

bones_nf = []
for obj in C.selected_objects:
    if obj.type == 'ARMATURE':
        for bone in obj.pose.bones:
            bones_nf.append({
                "obj":obj,
                "bone":bone
                })

bones = []
bone :bpy.types.PoseBone
for boneD in bones_nf:
    bone = boneD["bone"]
    if not bone.name.startswith("rig_"):
        bones.append(boneD)

bone_binds  = {}
bone_binds_inverse  = []

print("Assigning numbers to bones:")
i = 0
for boneD in bones:
    bone = boneD["bone"]
    print(bone.name, i)
    bone_binds[bone.name] = i
    bone_binds_inverse.insert(i,bone.name)
    i+=1 

actions = {}


#https://blenderartists.org/t/getting-the-actual-rotation-value-for-a-pose-bone-when-bone-rotation-is-altered-by-a-constraint/1375748/4
#but modified a bit
def quatRotation(poseBone: bpy.types.PoseBone, obj: bpy.types.Object):
    # poseBone.matrix is in object space - we need to convert it to local space 
    if poseBone.parent is not None:
        parentRefPoseMtx = poseBone.parent.bone.matrix_local
        boneRefPoseMtx = poseBone.bone.matrix_local
        parentPoseMtx = poseBone.parent.matrix
        bonePoseMtx = poseBone.matrix
        boneLocMtx = ( parentRefPoseMtx.inverted() @ boneRefPoseMtx ).inverted() @ ( parentPoseMtx.inverted() @ bonePoseMtx )
    else:
        boneRefPoseMtx = poseBone.bone.matrix_local
        bonePoseMtx = poseBone.matrix
        boneLocMtx = obj.matrix_world @ poseBone.matrix

    loc, rot, scale = boneLocMtx.decompose()
    return loc, rot

for action in bpy.data.actions:
    frame_start = int(action.frame_start)
    frame_end = int(action.frame_end)
    print("Action ",action.name)
    print("Frame start",frame_start,"Frame end",frame_end)
    info = {
        "name": action.name,
        "fps": scene.render.fps,
        "frame_start":frame_start,
        "frame_end":frame_end,
    }
    frames = []

    for ob in scene.objects:
        if ob.type == 'ARMATURE':
            ob.animation_data.action = action
            ob.animation_data.action_slot = ob.animation_data.action.slots[0]
            print("Action Slot",ob.animation_data.action_slot.name_display)
    

    for frame in range(frame_start, frame_end+1):
        print("Frame",frame)
        scene.frame_set(frame)
        C.view_layer.update()
        bones_at_frame = []
        for boneD in bones:
            bone = boneD["bone"]
            rot:mathutils.Quaternion
            loc, rot = quatRotation(bone, boneD["obj"])
            #print(loc)
            #rot = rot.to_euler()
            bones_at_frame.append(
            {
                "p": [
                    round(loc.x,3),
                    round(loc.y,3),
                    round(loc.z,3),
                ],
                "a": [
                    round(math.degrees(rot.w),3), 
                    round(math.degrees(rot.x),3), 
                    round(math.degrees(rot.y),3),  
                    round(math.degrees(rot.z),3), 
                    ],
            })
            
        frames.append(bones_at_frame)
    
    actions[action.name] = {
        "info": info,
        "frames": frames,
        "binds": bone_binds_inverse,
    }

bpy.context.window_manager.clipboard = json.JSONEncoder(separators=(',', ':')).encode({
    "actions": actions,
    "binds": bone_binds_inverse,
})
