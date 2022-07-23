local ACF = ACF
local Network = ACF.Networking

ACF.Armor = {}

local util = util
local table = table
local debugoverlay = debugoverlay
local MetaVector = FindMetaTable("Vector")
local Dot = MetaVector.Dot
local Cross = MetaVector.Cross

-- TODO: FINISH TO-DO LIST!

-- TODO: Remove time benchmarks from damage functions
-- TODO: Cleanup debug prints
-- TODO: More downsides to certain materials?

local debugtime = SERVER and 5 or 0.015

-- Lots of the necessary/unnecessary functions and stuff to support volumetric armor.
-- Made by LiddulBOFH
-- have fun!

local function MinVector(V1,V2) return Vector(math.min(V1.x,V2.x),math.min(V1.y,V2.y),math.min(V1.z,V2.z)) end
local function MaxVector(V1,V2) return Vector(math.max(V1.x,V2.x),math.max(V1.y,V2.y),math.max(V1.z,V2.z)) end

local function VolumeMesh(Mesh)
	local totalVolume = 0

	for _,v in pairs(Mesh) do
		local volume = 0
		for i = 1,#v,3 do
			volume = volume + Dot(v[i],Cross(v[i + 1],v[i + 2])) / 6
		end
		totalVolume = totalVolume + math.abs(volume)
	end

	return totalVolume
end

local function TriArea(p1,p2,p3) -- Area of a single triangle
	return Cross(p2 - p1,p3 - p1):Length()
end

local function SurfaceAreaOfHull(hull) -- Total surface area of a single hull in a mesh
	local area = 0
	for i = 1,#hull,3 do
		area = area + TriArea(hull[i],hull[i + 1],hull[i + 2])
	end
	return area
end

local function SurfaceAreaOfMesh(mesh) -- Total surface area of all components of a mesh
	local area = 0
	for _,hull in pairs(mesh) do
		area = area + SurfaceAreaOfHull(hull)
	end
	return area
end

local function CheckInsideClips(ent,point) -- This is to check the "cage" that can be made from clips
	if not ent.ClipData then return true end -- no clips, so its always "inside"

	local localPoint = ent:WorldToLocal(point)
	local localCenter = ent.OBBCenterOrg or ent:OBBCenter()

	for _,clip in ipairs(ent.ClipData) do
		if clip.physics then continue end
		local clipNormal = clip.n:Forward()
		local clipOrigin = clip.origin or (localCenter + clipNormal * clip.d)

		-- Subtracting clipNormal so we have a little leeway, for rounding errors and surfaces
		local inside = Dot((localPoint - (clipOrigin - (clipNormal * 0.01))):GetNormalized(),clipNormal) > 0

		if not inside then return false end
	end

	return true
end

local function InsideMeshHull(ent,hull,point,center,scale)
	local localPos = ent:WorldToLocal(point)

	local p1,p2,p3
	for I = 1, #hull, 3 do -- Loop over each tri (groups of 3)

		p1 = ((hull[I] - center) * scale) + center
		p2 = ((hull[I + 1] - center) * scale) + center
		p3 = ((hull[I + 2] - center) * scale) + center

		local edge1  = p2 - p1
		local edge2  = p3 - p1
		local dir = (localPos - ((p1 + p2 + p3) / 3)):GetNormalized()

		if Dot(dir,Cross(edge1,edge2)) < 0 then return false end -- Outside of the hull
	end

	return true
end

local function CheckClipPoint(ent,hull,index,origin,dir,checkOutward)
	local localOrigin = ent:WorldToLocal(origin)
	local localDir = ent:WorldToLocalAngles(dir:Angle()):Forward()
	local localCenter = ent.OBBCenterOrg or ent:OBBCenter()

	for _,Clip in ipairs(ent.ClipData) do
		local clipNormal = Clip.n:Forward()
		local clipOrigin = Clip.origin or (localCenter + clipNormal * Clip.d)
		local clipPoint = util.IntersectRayWithPlane(localOrigin - localDir,localDir,clipOrigin,clipNormal)

		if not clipPoint then goto SKIP_CHECKCLIP end -- The above will return nil if the ray never hits. The ray is from a definite point (origin) and infinite in direction

		--local ForwardOfPoint = (localDir:Dot((clipPoint - localOrigin):GetNormalized()))

		-- Clip planes always face "inward", anything behind it is clipped
		-- It is both inside of the mesh, AND the clipplane is in the same direction
		local planeCheckSide = checkOutward and (Dot(localDir,clipNormal) < 0) or (Dot(localDir,clipNormal) > 0)
		local Inside = InsideMeshHull(ent,hull,ent:LocalToWorld(clipPoint),ent._MeshHitbox[index].center,1.1) and planeCheckSide and CheckInsideClips(ent,ent:LocalToWorld(clipPoint))
		if Inside then
			--debugoverlay.Axis(ent:LocalToWorld(clipPoint),ent:LocalToWorldAngles(Clip.n),2,debugtime,false)
			--debugoverlay.Box(ent:LocalToWorld(clipPoint),Vector(-0.1,-0.1,-0.1),Vector(0.1,0.1,0.1),debugtime,Color(math.Rand(1,255),math.Rand(1,255),math.Rand(1,255)))
			debugoverlay.BoxAngles(ent:LocalToWorld(clipPoint),Vector(0,-1,-1),Vector(0,1,1),ent:LocalToWorldAngles(clipNormal:Angle()),debugtime,checkOutward and Color(255,0,0,5) or Color(0,255,255,5))
			return true,ent:LocalToWorld(clipPoint)
		end

		::SKIP_CHECKCLIP::
	end

	return false
end

local function FindInsertionPoint(ent, hull, index, origin, dir) -- just called once at the very end, finds the absolute first spot a mesh gets entered
	local min = math.huge
	local p1,p2,p3
	local finishPos = origin

	for I = 1, #hull, 3 do -- Loop over each tri (groups of 3)
		p1 = ent:LocalToWorld(hull[I]) -- Points on tri
		p2 = ent:LocalToWorld(hull[I + 1])
		p3 = ent:LocalToWorld(hull[I + 2])
		local edge1  = p2 - p1
		local edge2  = p3 - p1

		if Dot(dir,Cross(edge1,edge2)) < 0 then -- Plane facing the wrong way
			goto SKIP_INSERTIONCHECK
		end

		local H = Cross(dir,edge2) -- Perpendicular to dir
		local A = Dot(edge1,H)

		if A > -0.0001 and A < 0.0001 then -- Parallel
			goto SKIP_INSERTIONCHECK
		end

		local F = 1 / A
		local S = origin - p1 -- Displacement from to origin from P1
		local U = F * Dot(S,H)

		if U < 0 or U > 1 then
			goto SKIP_INSERTIONCHECK
		end

		local Q = Cross(S,edge1)
		local V = F * Dot(dir,Q)

		if V < 0 or U + V > 1 then
			goto SKIP_INSERTIONCHECK
		end

		local T = F * Dot(edge2,Q) -- Length of ray to intersection

		if T > 0.0001 and T < min then -- >0 length
			min = T
		end

		::SKIP_INSERTIONCHECK::
	end

	finishPos = origin + dir * min

	if ent.ClipData then
		local passClipCheck,clipPoint = CheckClipPoint(ent,hull,index,finishPos,dir,false)
		if passClipCheck then finishPos = clipPoint end
	end

	debugoverlay.Cross(finishPos, 3, debugtime, Color(0, 0, 255), true)
	return finishPos
end

local function FindOtherSideSingle(ent, hull, index, origin, dir)
	local min = math.huge
	local p1,p2,p3
	local finishPos = origin

	for I = 1, #hull, 3 do -- Loop over each tri (groups of 3)
		p1 = ent:LocalToWorld(hull[I]) -- Points on tri
		p2 = ent:LocalToWorld(hull[I + 1])
		p3 = ent:LocalToWorld(hull[I + 2])
		local edge1  = p2 - p1
		local edge2  = p3 - p1

		if Dot(dir,Cross(edge1,edge2)) > 0 then -- Plane facing the wrong way
			goto SKIP_OPPOSITECHECK
		end

		local H = Cross(dir,edge2) -- Perpendicular to dir
		local A = Dot(edge1,H)

		if A > -0.0001 and A < 0.0001 then -- Parallel
			goto SKIP_OPPOSITECHECK
		end

		local F = 1 / A
		local S = origin - p1 -- Displacement from to origin from P1
		local U = F * Dot(S,H)

		if U < 0 or U > 1 then
			goto SKIP_OPPOSITECHECK
		end

		local Q = Cross(S,edge1)
		local V = F * Dot(dir,Q)

		if V < 0 or U + V > 1 then
			goto SKIP_OPPOSITECHECK
		end

		local T = F * Dot(edge2,Q) -- Length of ray to intersection

		if T > 0.0001 and T < min then -- >0 length
			min = T
		end

		::SKIP_OPPOSITECHECK::
	end

	finishPos = origin + dir * min

	if ent.ClipData then
		local PassClipCheck,ClipPoint = CheckClipPoint(ent,hull,index,finishPos,-dir,false)
		if PassClipCheck then finishPos = ClipPoint end
	end

	--debugoverlay.Cross(finishPos, 3, debugtime, Color(0, 0, 255), true)
	return finishPos
end

local function RecursiveHullCheck(Start,endPos,ent,filter)
	local finished = false
	local finishPos = Start

	local inFilter = {ent}
	table.Add(inFilter,filter)

	--print("RECURSIVE")
	--PrintTable(inFilter)

	local Iter = 0

	while not finished do
		Iter = Iter + 1
		local T = util.TraceLine({start = Start,endpos = endPos,filter = inFilter})
		if not T.Hit then finishPos = T.HitPos finished = true break end
		if IsValid(T.Entity) then
			if not T.Entity._Mesh then
				local pass = ACF.Armor.BuildMesh(T.Entity)
				if not pass then return end
			end

			for k,v in pairs(T.Entity._Mesh) do
				local Inside = InsideMeshHull(T.Entity,v,T.HitPos,T.Entity._MeshHitbox[k].center,1.1)
				if Inside then
					debugoverlay.Cross(T.HitPos, 5, debugtime, Color(255, 0, 255), true)
					finishPos = FindInsertionPoint(T.Entity,v,k,T.HitPos,(endPos - Start):GetNormalized())
					finished = true
					break
				end
			end

			finishPos = T.HitPos
			table.insert(inFilter,T.Entity)
		end
		if Iter > 20 then finished = true break end
	end

	return finishPos
end

local function CheckLocalHitboxes(ent,origin,dir,hitboxList,inputHitboxList)
	local ang = ent:GetAngles()
	for k,v in ipairs(hitboxList) do
		local _, _, hitFrac = util.IntersectRayWithOBB(origin,dir * ent.diagonalSize,ent:LocalToWorld(v.center),ang,v.min,v.max)

		if hitFrac then
			local insertPoint = origin
			if ent.ClipData then
				local PassClipCheck,ClipPoint = CheckClipPoint(ent,ent._Mesh[k],k,insertPoint,dir)
				if PassClipCheck then insertPoint = ClipPoint end
			end

			oppositePoint = FindOtherSideSingle(ent,ent._Mesh[k],k,origin,dir)
			if (oppositePoint:Length() == math.huge) then goto SKIP_CHECKHITBOX end -- Basically it wasn't calculated right or some manner, and is invalid to check with
			--debugoverlay.Cross(oppositePoint, 1, debugtime, ong, true)

			local A = CheckInsideClips(ent,insertPoint)
			local B = CheckInsideClips(ent,oppositePoint)

			local Data = {index = k, dist = hitFrac * ent.diagonalSize, enter = origin, exit = oppositePoint, enterInsideClip = A, exitInsideClip = B}

			table.insert(inputHitboxList,Data)
			debugoverlay.BoxAngles(ent:LocalToWorld(v.center),v.min,v.max,ent:GetAngles(),debugtime,Color(0,255,0,0.1))
		end

		::SKIP_CHECKHITBOX::
	end
end

local function CheckHitboxHit(ent,origin,dir,filter)
	local Hitboxes = ent._MeshHitbox
	if not Hitboxes then print("Hitboxes not made on " .. tostring(ent)) return end

	ent.diagonalSize = (ent:OBBMaxs() - ent:OBBMins()):Length()

	local BoxList = {}

	CheckLocalHitboxes(ent,origin,dir,Hitboxes,BoxList)

	if #BoxList == 0 then return end -- Never even hit a single hitbox (somehow)

	table.sort(BoxList,function(a,b) return a.dist < b.dist end)

	if (not BoxList[1].enterInsideClip) and (#BoxList > 1) then
		local PostClipBoxList = {}
		local FirstHit = false
		for _,v in ipairs(BoxList) do
			if not FirstHit and v.enterInsideClip then FirstHit = true end
			if FirstHit then table.insert(PostClipBoxList,v) end
		end

		BoxList = PostClipBoxList
	end

	if #BoxList == 0 then return end -- All of the meshes checked were clipped and filtered out

	local FinalList = {BoxList[1]}
	debugoverlay.BoxAngles(ent:LocalToWorld(ent._MeshHitbox[BoxList[1].index].center),ent._MeshHitbox[BoxList[1].index].max,ent._MeshHitbox[BoxList[1].index].max,ent:GetAngles(),debugtime,Color(0,255,0,1))

	if #BoxList > 1 then
		for k,_ in ipairs(BoxList) do
			if k + 1 > #BoxList then break end

			local CurrentBox = BoxList[k]
			local NextBox = BoxList[k + 1]

			local CanPass = InsideMeshHull(ent,ent._Mesh[NextBox.index],CurrentBox.exit,ent._MeshHitbox[NextBox.index].center,1.1) and CheckInsideClips(ent,CurrentBox.exit)

			debugoverlay.BoxAngles(ent:LocalToWorld(ent._MeshHitbox[NextBox.index].center),ent._MeshHitbox[NextBox.index].max,ent._MeshHitbox[NextBox.index].max,ent:GetAngles(),debugtime,Color(0,255,0,1))

			if CanPass then
				--debugoverlay.Line(FinalList[#FinalList].exit,NextBox.enter,debugtime,Flip and Color(0,255,0) or Color(0,0,255),true)
				FinalList[#FinalList + 1] = NextBox
			else
				--debugoverlay.Line(FinalList[#FinalList].exit,NextBox.enter,debugtime,Color(255,0,0),true)
				break
			end
			Flip = not Flip
		end
	else
		if not (FinalList[1].enterInsideClip or FinalList[1].exitInsideClip) then return end
	end

	for k,v in ipairs(FinalList) do
		debugoverlay.EntityTextAtPosition(ent:LocalToWorld(ent._MeshHitbox[v.index].center),0,"Box: " .. k .. ", Hull: " .. v.index,debugtime)
	end

	local InsertionPoint = FindInsertionPoint(ent,ent._Mesh[FinalList[1].index],FinalList[1].index,origin,dir) -- problem

	local FinalExit = RecursiveHullCheck(InsertionPoint,FinalList[#FinalList].exit,ent,filter)

	return InsertionPoint,FinalExit,true
end

local function TraceThroughObject(trace,Bullet)
	local ent    = trace.Entity
	local origin = trace.StartPos
	local enter  = trace.HitPos
	local dir   = (enter - origin):GetNormalized()
	local filter = Bullet and Bullet.Filter or {}
	if dir:Length() == 0 then
		if SERVER then
			if Bullet then
				dir = Bullet.Flight:GetNormalized()
			else
				return 100000, enter, enter
			end
		else
			dir = LocalPlayer():EyeAngles():Forward()
		end
		enter = enter - (dir * (ent.diagonalSize or (ent:OBBMaxs() - ent:OBBMins()):Length()))
	end

	local t2 = util.TraceLine({start = enter - dir,endpos = enter + dir,
		filter = function(te)
			if te ~= ent then
				table.insert(filter,te)
				return false
			else return true end
		end})

	if not ent._Mesh then print("No mesh still somehow") return 0,enter end

	local startPos,endPos,pass = CheckHitboxHit(ent,enter,dir,filter,trace)
	if pass and startPos and endPos then -- still managing to get a nil return for startPos and endPos, so we'll filter it again
		return (endPos - startPos):Length() * 25.4, endPos, startPos
	else return 0, enter, enter end
end

local function CenterOfMesh(hull) -- since this isn't called in a spot where we readily have sanitised data, have to fall back to the ol' double call
	local pos = (type(hull[1]) == "Vector") and hull[1] or hull[1].pos
	for i = 2, #hull do
		pos = pos + ((type(hull[i]) == "Vector") and hull[i] or hull[i].pos)
	end
	return pos / #hull
end

local function FinishMesh(ent,mesh)
	local newMesh = {}
	local meshHitbox = {}

	local minCorner,maxCorner

	for ind,hull in ipairs(mesh) do
		newMesh[ind] = {}

		local center = CenterOfMesh(hull)

		local boxMin,boxMax = center,center

		for ind2,point in ipairs(hull) do
			local pos = (type(point) == "Vector") and point or point.pos
			newMesh[ind][ind2] = pos
			boxMin = MinVector(pos,boxMin)
			boxMax = MaxVector(pos,boxMax)

			minCorner = MinVector(pos,minCorner or pos)
			maxCorner = MaxVector(pos,maxCorner or pos)
		end

		debugoverlay.BoxAngles(ent:LocalToWorld(center),boxMin,boxMin,ent:GetAngles(),5,Color(math.Rand(1,255),math.Rand(1,255),math.Rand(1,255),65))
		meshHitbox[ind] = {center = center, min = boxMin - center, max = boxMax - center}
	end

	ent._Mesh = newMesh
	ent._MeshHitbox = meshHitbox

	ent._MeshTotalSize = maxCorner - minCorner
	ent._MeshCenter = (maxCorner + minCorner) / 2
	ent._MeshMin = minCorner
	ent._MeshMax = maxCorner

	debugoverlay.BoxAngles(ent:LocalToWorld(Vector()),ent._MeshMin,ent._MeshMax,ent:GetAngles(),5,Color(255,0,0,1))
end

-- Global, shared Armor functions (volumetric)

function ACF.Armor.RHAe(length,density)
	return length * (density / 7.84)
end

local Armors = ACF.Classes.ArmorTypes
local DensityList = {}
local function PopulateDensityList()
	for k,v in pairs(Armors) do
		DensityList[#DensityList + 1] = {index = k,density = v.Density,tensile = v.Tensile,yield = v.Yield}
	end

	table.sort(DensityList,function(a,b) return a.density < b.density end)
end

function ACF.Armor.CalculateHealthMod(density)
	if not next(DensityList) then PopulateDensityList() end
	local UpperIndex = 1

	for i = 1, #DensityList do
		if DensityList[UpperIndex].density < density then UpperIndex = i end
	end

	local LowerIndex = math.max(UpperIndex - 1,1)

	local LowerArmor = DensityList[LowerIndex]
	local UpperArmor = DensityList[UpperIndex]

	local Mix = math.Clamp((density - LowerArmor.density) / (UpperArmor.density - LowerArmor.density),0,1)

	--print(DensityList[LowerIndex].index,(1 - math.Round(Mix,4)) * 100 .. "%",DensityList[UpperIndex].index,math.Round(Mix,4) * 100 .. "% mix")

	local MixedTensile = math.Round(Lerp(Mix,LowerArmor.tensile,UpperArmor.tensile),2)
	local MixedYield = math.Round(Lerp(Mix,LowerArmor.yield,UpperArmor.yield),2)

	--print(density .. "g/cm3","yield: " .. MixedYield .. "MPa","tensile: " .. MixedTensile .. "MPa")

	local TensileYieldDiff = (MixedTensile - MixedYield)
	local HealthMod = MixedYield + (TensileYieldDiff / 2)

	--print(HealthMod)

	return HealthMod
end

function ACF.Armor.GetDistanceThroughMesh(trace,PlayerEye)
	local ent    = trace.Entity
	local origin = trace.StartPos
	local enter  = trace.HitPos
	local dir   = (enter - origin):GetNormalized()
	local filter = Bullet and Bullet.Filter or {}
	if dir:Length() == 0 then
		dir = PlayerEye
		enter = enter - (dir * (ent.diagonalSize or (ent:OBBMaxs() - ent:OBBMins()):Length()))
	end

	local iter = 0
	while not (ent._Mesh or iter > 4) do
		ACF.Armor.BuildMesh(ent)
		iter = iter + 1
	end

	if not ent._Mesh then print("No mesh still somehow") return 0,enter end

	local startPos,endPos,pass = CheckHitboxHit(ent,enter,dir,filter,trace)
	if pass then
		return (endPos - startPos):Length() * 25.4, endPos, startPos
	else return 0, enter, enter end
end

-- TODO: Make this a scale around 7.84g/cm3
-- maybe 4~ wide range around where it has almost as much health, and past that it sheerly drops? maybe less of a drop below minimum, but sheer drop above limit
function ACF.Armor.CalculateHealth(ent,density,volumeOverride)
	if not IsValid(ent) then return 0 end
	local Volume
	if not volumeOverride then
		local physobj = ent:GetPhysicsObject()
		Volume = ent._MeshVolume or (IsValid(physobj) and physobj:GetVolume() or ent:GetNW2Float("ACF.Volume",0))
		if Volume == 0 then
			local BS = ent:OBBMaxs() - ent:OBBMins()
			Volume = BS.x * BS.y * BS.z
		end
	else Volume = volumeOverride end
	return math.max(math.Round(Volume * ACF.Armor.CalculateHealthMod(density),1),1)
end

function ACF.Armor.BuildMesh(ent)
	if CLIENT then
		if ACF.ModelData.IsOnStandby(ent:GetModel()) then print("Delay getting armor for " .. tostring(ent) .. ", waiting on server for ModelData (repeat)") return false end
		if not IsValid(ent:GetPhysicsObject()) and not (ACF.ModelData.IsOnStandby(ent:GetModel())) then -- doesn't exist, so we call the server to send us something
			local Data = ACF.ModelData.GetModelData(ent:GetModel())
			if Data then
				FinishMesh(ent,Data.Mesh)
				return true
			else
				print("Delay getting armor for " .. tostring(ent) .. ", waiting on server for ModelData")
				return false
			end
		else
			if IsValid(ent:GetPhysicsObject()) then
				FinishMesh(ent,ent:GetPhysicsObject():GetMeshConvexes())
				return true
			else
				print("Error getting armor for " .. tostring(ent) .. " due to invalid PhysObj")
				return false
			end
		end
	else -- it does exist, so we'll use what we can
		if IsValid(ent:GetPhysicsObject()) then
			FinishMesh(ent,ent:GetPhysicsObject():GetMeshConvexes())
			return true
		else
			print("Error getting armor for " .. tostring(ent) .. " due to invalid PhysObj")
			return false
		end
	end
end

function ACF.Armor.GetArmor(trace,density,Bullet)
	if not trace then return 0 end
	local ent = trace.Entity
	if not IsValid(ent) then
		print("invalid")
		return 0
	end

	if not ent._Mesh then
		local Pass = ACF.Armor.BuildMesh(ent)
		if not Pass then print("ACF.Armor.BuildMesh failed") return 0 end
	end

	local enter        = trace.HitPos
	local armorLength, exit, enter = TraceThroughObject(trace,Bullet)
	local Pen = 0
	if Bullet then Pen = math.Round(Bullet:GetPenetration(),1) end

	--debugoverlay.Cross(enter, 1, debugtime, Color(0, 255, 0), true)
	--debugoverlay.Cross(exit, 2, debugtime, Color(255, 0, 0), true)
	debugoverlay.Line(exit + ((enter - exit):GetNormalized() * (armorLength / 25.4)), exit, debugtime, Color(0, 255, 255), true)
	debugoverlay.Text(exit,math.ceil(ACF.Armor.RHAe(armorLength,density)) .. "mm vs " .. Pen .. "mm",debugtime,false)

	--print("ARMOR FROM IMPACT WITH " .. tostring(ent) .. ":" .. ACF.Armor.RHAe(armorLength,density))
	return ACF.Armor.RHAe(armorLength,density),exit,enter
end

if SERVER then
	function ACF.Armor.Update(entity)
		duplicator.StoreEntityModifier(entity, "mass", {Mass = entity.ACF.Mass})

		entity:SetNW2Float("ACF.Density",entity.ACF.Density)

		ACF.Activate(entity,true)
	end

	function ACF.Armor.SetMassByDensity(entity,density)
		if not entity.ACF then return end
		local PhysObj = entity:GetPhysicsObject()
		if not IsValid(PhysObj) then print("Invalid PhysObj") return end
		local Volume = PhysObj:GetVolume()

		--print("MASS: " .. ((density * Volume) / 1000) * ACF.gCmToKgIn,"VOLUME: " .. Volume)

		entity.ACF.Mass = math.Round((density * Volume) * ACF.gCmToKgIn,4)
		PhysObj:SetMass(entity.ACF.Mass)
		entity.ACF.Mass = PhysObj:GetMass()

		ACF.Armor.Update(entity)
	end

	function ACF.Armor.UpdateDensityByMass(entity)
		if not entity.ACF then return end
		local PhysObj = entity:GetPhysicsObject()
		if not IsValid(PhysObj) then print("Invalid PhysObj") return end
		local Volume = entity._MeshVolume or PhysObj:GetVolume()

		local Mass = PhysObj:GetMass()
		if (not entity.DupeMassChecked) and entity.EntityMods and entity.EntityMods.mass then -- EZ fix for dupes not getting old weight
			Mass = entity.EntityMods.mass["Mass"]
			entity.DupeMassChecked = true
		end
		entity.ACF.Mass = Mass

		if Volume == 0 then
			local BS = entity:OBBMaxs() - entity:OBBMins()
			Volume = BS.x * BS.y * BS.z
		end
		local density = (Mass / Volume) / ACF.gCmToKgIn

		entity.ACF.Density = density

		ACF.Armor.Update(entity)
	end

	function ACF.Armor.UniversalGetArmor(self,trace)
		if not IsValid(self) then print("========= ASKED FOR ARMOR ON INVALID ENTITY") return 0 end
		local ent = self
		if not ent.ACF then ACF.Activate(ent) end

		if ent.GetArmor then return ent:GetArmor(trace) else PrintTable(ent.ACF) return ent.ACF.Armour end
	end

	function ACF.Armor.VolumetricArmor_GetArmor(self,trace)
		if not IsValid(trace.Entity) then return 0 end

		return ACF.Armor.GetArmor(trace,trace.Entity.ACF.Density)
	end

	function ACF.Armor.VolumetricArmor_OnDamage(self,Bullet, trace, Volume) -- To be assigned on activation to a prop, so consider this a meta function
		local HP     = self.ACF.Health

		if Bullet.IsTorch then -- no need to do anything past here, someone can simply just pass IsTorch, Owner, and optionally TorchDamage through the bullet data
			local TorchDamage = math.min(Bullet.TorchDamage or ACF.TorchDamage,trace.Entity.ACF.MaxHealth * 0.01)
			self.ACF.Health = HP - TorchDamage
			return {
				Damage = TorchDamage,
				Loss = 0,
				Overkill = 0,
				Kill = TorchDamage > HP
			}
		end

		local Armor  = ACF.Armor.GetArmor(trace,self.ACF.Density,Bullet)
		local Pen    = Bullet:GetPenetration() -- RHA Penetration
		local MaxPen = math.min(Armor, Pen)
		local Damage = isnumber(Volume) and Volume or (MaxPen * ((Bullet.Caliber * 5) ^ 2) * math.pi) -- Damage is simply the volume of the hole made
		local Loss	 = math.Clamp(MaxPen / Pen, 0, 1)

		if Loss == 1 and not Bullet.IsFrag and not Volume then
			local Rico,_ = ACF_CalcRicochet(Bullet, trace)
			local Ang = 90 * Rico
			if Ang > (Bullet.Ricochet or 60) then
				Damage = Damage * math.max(1 - Rico,0.25)
			end
		end

		self.ACF.Health = HP - Damage -- Update health

		return { -- Damage report
			Loss = math.Clamp(MaxPen / Pen, 0, 1), -- Energy loss ratio
			Damage = Damage,
			Overkill = math.max(Pen - MaxPen, 0),
			Kill = Damage > HP
		}
	end

	local ENT = FindMetaTable("Entity")
	PhysInitSphere = PhysInitSphere or ENT.PhysicsInitSphere

	function ENT:PhysicsInitSphere(Radius,PhysMat)
		if IsValid(self:GetPhysicsObject()) then
			FinishMesh(self,self:GetPhysicsObject():GetMeshConvexes())
			self._MeshVolume = VolumeMesh(self._Mesh)
		end

		PhysInitSphere(self,Radius,PhysMat)
	end

	Network.CreateSender("ACF.Primitive.CleanClientMesh",function(Queue,Ent)
		local ID = Ent:EntIndex()
		Queue[ID] = ID
	end)

	hook.Remove("primitive.updatePhysics","ACF Primitive Watchdog") -- TODO: Remove this hook.Remove, was here so I could update this file without issue
	hook.Add("primitive.updatePhysics","ACF Primitive Watchdog",function(self, constraints, mass, physprops) --2 is constraint table, 4 is physprops (gravity, material)
		if self.ACF then
			self:primitive_RestorePhysics(mass, physprops) -- Regularly call the functions to maintain function
			self:primitive_RestoreConstraints(constraints)

			ACF.Armor.SetMassByDensity(self,self.ACF.Density)

			self._Mesh = nil
			self._MeshHitbox = nil
			Network.Broadcast("ACF.Primitive.CleanClientMesh",self)

			return false
		end
	end)
else
	local function benchmark(ply,_,args)
		local time = SysTime()
		local runs = args[1] or 1

		local trace = ply:GetEyeTrace()
		local ent = trace.Entity

		if IsValid(ent) and (ent:GetNW2Bool("ACF.Volumetric") == true) then
			local density = ent:GetNW2Float("ACF.Density",1)
			for _ = 1,runs do
				ACF.Armor.GetArmor(trace,density,_)
			end
			local timediff = SysTime() - time
			MsgN("ACF.Armor.GetArmor Benchmark: " .. timediff .. "s for " .. runs .. "runs")
		else
			MsgN("Look at a valid entity with volumetric armor!")
		end
	end

	concommand.Add("acf_benchmark_volumetricarmor",benchmark)

	Network.CreateReceiver("ACF.Primitive.CleanClientMesh",function(EntIDList)
		for _,v in pairs(EntIDList) do
			local Ent = Entity(v)
			if not IsValid(Ent) then print("invalid") continue end
			Ent._Mesh = nil
			Ent._MeshHitbox = nil
			print("Cleaned data for " .. tostring(Ent))
		end
	end)
end
