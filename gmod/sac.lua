--@name SimpleAnimCore
--@author PowerBuxoK

local Sent = false

local animObj = class("SimpleAnimCore armature")

local animCoreMainFunc

function animObj:initialize()
    self.batchCounter = 0
    self.objects = {}
    self.actions = {}
    self.cur_acimation = {}
    hook.add("renderoffscreen","animCoreMainFunc_"..table.address(self),function() self:animCoreMainFunc() end)
end

function animObj:addObject(obj,bone,ignore_list,preUpdate)
    assert(obj,"No object specified")
    bone = bone or "*"
    ignore_list = ignore_list or {}
    ignore_list_inverted = {}
    for i,v in pairs(ignore_list) do
        ignore_list_inverted[v] = true
    end
    self.objects[#self.objects+1] = {
        origin_pos = chip():getPos(),
        origin_ang = chip():getAngles(),
        offset_pos = Vector(),
        offset_ang = Angle(),
        ent = obj,
        bone = bone,
        ignore = ignore_list_inverted,
        preUpdate = preUpdate
    }
    --return #self.objects
    return {
        id = #self.objects,
        aniobj = self,
        setOrigin = function(self,pos,ang)
            self.aniobj:setOrigin(self.id,pos,ang)
        end,
        setOffset = function(self,pos,ang)
            self.aniobj:setOffset(self.id,pos,ang)
        end
        }
end

function animObj:setOrigin(id,pos,ang)
    assert(pos,"Pos not defined")
    assert(ang,"Ang not defined")
    assert((type(pos[1]) == "number" and type(pos[2]) == "number" and type(pos[3]) == "number"), "Pos is not position")
    assert((type(pos[1]) == "number" and type(pos[2]) == "number" and type(pos[3]) == "number"),"Ang is not angle")
    self.objects[id].origin_pos = pos
    self.objects[id].origin_ang = ang
end

function animObj:setOffset(id,pos,ang)
    assert(pos,"Pos not defined")
    assert(ang,"Ang not defined")
    assert((type(pos[1]) == "number" and type(pos[2]) == "number" and type(pos[3]) == "number"), "Pos is not position")
    assert((type(pos[1]) == "number" and type(pos[2]) == "number" and type(pos[3]) == "number"),"Ang is not angle")
    self.objects[id].offset_pos = pos
    self.objects[id].offset_ang = ang
end

function animObj:warn(...)
    if not Sent then
        print("Anim Core: Warning was sent to console, this message will never appear again")
    end
    printConsole("Warning: ".. ...)
    Sent = true
end

function animObj:addAction(action,bone_binds,name)
    local action = table.copy(action)
    assert(type(action) == "table","No action specified")
    assert(action.info,"Action has no info field")
    if not action.info.name then
        self:warn(string.format("Action has no name in info field, using %s from key",name))
        action.info.name = name
    end
    local name = action.info.name
    if not action.binds then
        self:warn(string.format("Action %s has no bone binds, using binds from action batch",name))
        action.binds = table.copy(bone_binds)
    end
    assert(action.binds,"Was unable to get action bone binds from action and action batch")
    assert(action.frames,"Action has no framedata")
    assert(action.frames,string.format("Action %s has no frame data",name))
    assert(action.info.fps,"Action %s has no FPS specified",name)
    if not action.info.frame_start then
        self:warn(string.format("Action %s has no start frame, using 0",name))
        action.info.frame_start = 0
    end
    if not action.info.frame_end then
        self:warn(string.format("Action %s has no end frame, using frame data length [%i frames] to estimate",name,#action.frames))
        action.info.frame_end = action.info.frame_start + #action.frames
    end
    action.info.length = action.info.frame_end - action.info.frame_start
    action.info.length_seconds = action.info.length/action.info.fps
    
    self.actions[name] = action
end

function animObj:getActions()
    return table.getKeys(self.actions)
end

function animObj:addActionBatch(batch,name)
    local name = name or "Unnamed_"
    assert(batch.actions,"This batch has no actions (what)")
    if not batch.binds then
        self:warn(string.format("Action batch %s has no binds.",name))
    end
    for i,v in pairs(batch.actions) do
        self:addAction(v,batch.binds,name..i)
    end
end

function animObj:playAnimSimple(name)
    if not self.actions[name] then
        self:warn(string.format("Action %s does not exist, unable to play", name))
        return
    end
    self.cur_animation = {
        tmr = 0,
        action = self.actions[name],
    }
end

function animObj:getAnim()
    if not self.cur_animation then return end
    return self.cur_animation.action.info.name
end

function animObj:getTimer(name)
    if not self.cur_animation then return end
    return self.cur_animation.tmr
end

local function frameLerpPrecalc(action,time)
    local info = action.info
    local frames = action.frames
    frameLast = math.clamp(math.floor(time * info.fps), info.frame_start, info.frame_end-1)+1
    frameNew = math.clamp(math.ceil(time * info.fps), info.frame_start, info.frame_end-1)+1
    timeSinceLastFrame = (time-math.floor(time/(1/info.fps))*(1/info.fps))*info.fps
    return {
        frameLast = frames[frameLast],
        frameNew = frames[frameNew],
        timeSinceLastFrame = timeSinceLastFrame,
        }
end

local function getLerpBoneData(lerpPrecalc,id)
    local frameLastBoneData = lerpPrecalc.frameLast[id]
    local frameNewBoneData = lerpPrecalc.frameNew[id]
    local QuatAngLast = Quaternion(frameLastBoneData.a[1], frameLastBoneData.a[2], frameLastBoneData.a[3], frameLastBoneData.a[4])
    local QuatAngNew = Quaternion(frameNewBoneData.a[1], frameNewBoneData.a[2], frameNewBoneData.a[3], frameNewBoneData.a[4])
    local PosLast = Vector(-frameLastBoneData.p[2],frameLastBoneData.p[1],frameLastBoneData.p[3])
    local PosNew = Vector(-frameNewBoneData.p[2],frameNewBoneData.p[1],frameNewBoneData.p[3])
    return {
        a = math.slerpQuaternion(QuatAngLast, QuatAngNew, lerpPrecalc.timeSinceLastFrame):getEulerAngle(),
        p = math.lerpVector(lerpPrecalc.timeSinceLastFrame,PosLast,PosNew),
        }
end

local lerpPrecalc

function animObj:animCoreMainFunc()
    if self.cur_animation == nil then return end
    local cur_animation = self.cur_animation
    local cur_action = cur_animation.action
    local binds = cur_action.binds
    cur_animation.tmr = cur_animation.tmr + timer.frametime()
    for _,obj in pairs(self.objects) do
        obj.preUpdate(obj)
        if obj.bone == "*" then
            obj.ent:setPos(obj.origin_pos)
            obj.ent:setAngles(obj.origin_ang)
        end
    end
    
    lerpPrecalc = frameLerpPrecalc(cur_action,cur_animation.tmr)
    
    for i,v in pairs(lerpPrecalc.frameLast) do
        for _,obj in pairs(self.objects) do
            local ent = obj.ent
            local bone = obj.bone
            if bone == "*" then
                local name = binds[i]
                local id = obj.ent:lookupBone(name)
                if id == nil or obj.ignore[name] then continue end
                local bdat = getLerpBoneData(lerpPrecalc,i)
                obj.ent:manipulateBoneAngles(id, bdat.a + obj.offset_ang)
                obj.ent:manipulateBonePosition(id, bdat.p + obj.offset_pos)
            else
                local id = table.keyFromValue(binds,bone)
                if not id then
                    self:warn(string.format("%s has no %s",ent,bone))
                    continue
                end
                local bdat = getLerpBoneData(lerpPrecalc,id)
                local worldPos, worldAng = localToWorld(bdat.p + obj.offset_pos, bdat.a + obj.offset_ang, obj.origin_pos, obj.origin_ang)
                ent:setPos(worldPos)
                ent:setAngles(worldAng)
            end
        end
    end
    
    if self.cur_animation.tmr > self.cur_animation.action.info.length_seconds then self.cur_animation = nil end
end

return animObj

