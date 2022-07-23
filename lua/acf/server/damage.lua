-- Local Vars -----------------------------------
local ACF     = ACF
local HookRun = hook.Run
local pi = math.pi

do -- KE Shove
	function ACF.KEShove(Target, Pos, Vec, KE)
		if not IsValid(Target) then return end

		if HookRun("ACF_KEShove", Target, Pos, Vec, KE) == false then return end

		local Ancestor = ACF_GetAncestor(Target)
		local Phys = Ancestor:GetPhysicsObject()

		if IsValid(Phys) then
			if not Ancestor.acflastupdatemass or Ancestor.acflastupdatemass + 2 < ACF.CurTime then
				ACF_CalcMassRatio(Ancestor)
			end

			local Ratio = Ancestor.acfphystotal / Ancestor.acftotal
			local LocalPos = Ancestor:WorldToLocal(Pos) * Ratio

			Phys:ApplyForceOffset(Vec:GetNormalized() * KE * Ratio, Ancestor:LocalToWorld(LocalPos))
		end
	end
end

do -- Explosions ----------------------------
	local TraceData = { start = true, endpos = true, mask = MASK_SOLID, filter = false }

	local function GetRandomPos(Entity, IsChar)
		if IsChar then
			local Mins, Maxs = Entity:OBBMins() * 0.65, Entity:OBBMaxs() * 0.65 -- Scale down the "hitbox" since most of the character is in the middle
			local Rand		 = Vector(math.Rand(Mins[1], Maxs[1]), math.Rand(Mins[2], Maxs[2]), math.Rand(Mins[3], Maxs[3]))

			return Entity:LocalToWorld(Rand)
		else
			local Mesh = Entity:GetPhysicsObject():GetMesh()

			if not Mesh then -- Is Make-Sphericaled
				local Mins, Maxs = Entity:OBBMins(), Entity:OBBMaxs()
				local Rand		 = Vector(math.Rand(Mins[1], Maxs[1]), math.Rand(Mins[2], Maxs[2]), math.Rand(Mins[3], Maxs[3]))

				return Entity:LocalToWorld(Rand:GetNormalized() * math.Rand(1, Entity:BoundingRadius() * 0.5)) -- Attempt to a random point in the sphere
			else
				local Rand = math.random(3, #Mesh / 3) * 3
				local P    = Vector(0, 0, 0)

				for I = Rand - 2, Rand do P = P + Mesh[I].pos end

				return Entity:LocalToWorld(P / 3) -- Attempt to hit a point on a face of the mesh
			end
		end
	end

	local FragData = {
		IsFrag = true,
		Owner = true,
		Gun = true,
		NoEffect = true, -- Too much hassle trying to do something special for fragments, so we'll just not

		ProjArea = true,
		ProjMass = true,
		Caliber = true,
		Diameter = true,
		Flight = true,
		Speed = true,
		ShovePower = 0.2,
		Type = "AP",
		LimitVel = 800,
		Ricochet = 60,
		MaxLife = true
	}

	function FragData:GetPenetration()
		return ACF.Penetration(self.Speed, self.ProjMass, self.Diameter * 10)
	end

	local AmmoTypes = ACF.Classes.AmmoTypes
	local function CreateFrag(FragVel,ParentVel,InputFragData)
		local Dir = VectorRand(-1,1):GetNormalized()
		local Vel = (Dir * FragVel) + ParentVel * 2
		InputFragData.Flight = Vel:GetNormalized() * math.Clamp(Vel:Length(),0,300000)
		-- Fuzing an AP shell makes it simply disappear, as long as the OnFlightEnd remains as just a means to delete the shell
		-- Doesn't need to last too long, 1s ought to be enough?
		InputFragData.Fuze = math.min((InputFragData.Flight:Length() / 2048) * math.max(InputFragData.ProjMass,1),0.2)

		AmmoTypes["AP"]:Create(FragSource,InputFragData)
	end

	--[[
	{{OLD}} ACF.HE(Origin, FillerMass, FragMass, Inflictor, Filter, Gun)
	{{NEW}} ACF.HE(ExplosiveData, Filter, Gun, Trace, Bullet)
	ExplosiveData = {
		Origin 		= Vector(), -- Position of the explosion
		ExplosiveMass 	= 0, -- The explosive content
		ProjMass 	= 0, -- The projectile's mass, not counting the filler content
		FragMass	= 0, -- Optional, but overrides calculation for the same thing (for manual input of FragMass)
		Inflictor	= true, -- Whoever smelled it dealt it
	}
	]]

	-- TODO: When calculating blast, do a moving center, and check during each interval if this center ever leaves the blast radius
	-- This can be combined with blast energy to be a cheap way to simulate blast compression (exploded inside a tank)
	-- Thus, if energy drops below a threshold, the explosion should stop getting calculated

	-- TODO: Applying damage: Use the area of the sphere for dispersal, and then a slice of the volume of the entity in question?

	function ACF.HE(ExplosiveData, Filter, Gun, Trace, Bullet)
		if HookRun("ACF_BlastDamage", {Origin = ExplosiveData.Origin,Owner = ExplosiveData.Inflictor}) == false then return end
		Filter = Filter or {}
		local ShortFilter = {}
		if not Trace then table.insert(Filter,Gun) end -- Not always a gun that causes HE (ammo explosions, fuel tanks), so if this is the case we should filter it out
		-- Afterthought: After looking at CreateBullet, Filter is automatically written with Gun, but I'll leave this just incase

		for _,v in pairs(Filter) do ShortFilter[v] = true end

		--if true then return end

		ExplosiveData.Gun = Gun
		ExplosiveData.Owner = ExplosiveData.Inflictor
		local BlastData = ACF.GetBlastInfo(ExplosiveData)
		local FragEnergy = BlastData.Energy * 0.67

		local Amp 		 = math.min(BlastData.Energy / 2000, 50)

		TraceData.start = BlastData.Origin
		TraceData.filter = Filter

		util.ScreenShake(BlastData.Origin, Amp, Amp, Amp / 15, BlastData.Radius * 10)

		debugoverlay.Sphere(BlastData.Origin,BlastData.Radius,15,Color(255,0,0,5),false)
		debugoverlay.Cross(BlastData.Origin,BlastData.Radius, 15, Color( 255, 255, 255 ), true)

		local PreEnts = ents.FindInSphere(ExplosiveData.Origin,BlastData.Radius)

		local Ents = {}
		for _,ent in ipairs(PreEnts) do
			if not ACF.Check(ent) then table.insert(Filter,ent) continue end
			if (ent:IsPlayer() or ent:IsNPC()) and ent:Health() <= 0 then table.insert(Filter,ent) continue end -- deadite filter, just in case
			local diff = (ExplosiveData.Origin - ent:GetPos())
			table.insert(Ents,{ent,diff:LengthSqr(),diff:GetNormalized():Angle()})
		end -- 1 = Entity, 2 = DistSqr from Origin, 3 = Angle to entity from Origin
		table.sort(Ents,function(a,b) return a[2] < b[2] end)

		local WaveCenter = BlastData.Origin
		if Trace and Trace.HitNormal:LengthSqr() ~= 0 then
			WaveCenter = WaveCenter + (Trace.HitNormal * (BlastData.Energy ^ (1 / 4)))
		end

		BlastData.Origin = WaveCenter

		debugoverlay.Cross(WaveCenter,60,15,Color(255,0,0),true)

		-- Explosive wave itself
		for _,data in ipairs(Ents) do
			local ent = data[1]
			if BlastData.Energy <= 0 then print("Ran out of energy :(") break end
			local ePos = ent:LocalToWorld(ent.OBBCenterOrg or ent:OBBCenter())

			local Pos = GetRandomPos(ent,ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot())
			TraceData.endpos = Pos
			local t = ACF.TraceF(TraceData)
			if IsValid(t.Entity) and t.Entity == ent then
				local CrossSectionalArea = ACF.GetCrossSectionalArea(BlastData.Origin,ent)

				local nearestPos = ent:NearestPoint(BlastData.Origin)
				local Mix = LerpVector(0.75,ePos,nearestPos)

				local E = ACF.BlastDamage(BlastData,ent,Mix,CrossSectionalArea)

				if IsValid(ent) and (ent.ACF.Health > 0) then
					BlastData.Energy = BlastData.Energy - (E * 0.5)
					WaveCenter = WaveCenter + ((WaveCenter - Mix):GetNormalized() * E * 0.01)
					if ent.ACF.Type == "Prop" then
						ACF.KEShove(ent,ExplosiveData.Origin,(ExplosiveData.Origin - (Mix + VectorRand(-CrossSectionalArea / 10,CrossSectionalArea / 10))):GetNormalized(),E * 10)
					end
				else -- it died
					BlastData.Energy = BlastData.Energy - (E * 0.25)
					WaveCenter = WaveCenter - ((WaveCenter - Mix):GetNormalized() * E * 0.1)
				end
			else continue end

			--debugoverlay.Text(ent:GetPos(),"I: " .. ind,15,false)
		end

		debugoverlay.Cross(WaveCenter,60,15,Color(0,0,255),true)

		-- Fragmentation

		local ParentVel = Vector()
		if Bullet then
			ParentVel = Bullet.Flight * 0.25
		elseif Gun then
			local Ancestor = ACF_GetAncestor(Gun):GetPhysicsObject()
			if IsValid(Ancestor) then
				ParentVel = Ancestor:GetVelocity() * 0.25
			end
		end

		ParentVel = ParentVel + ((WaveCenter - ExplosiveData.Origin) * 5)

		--local ParentVel = (Bullet and (Bullet.Flight * 0.2)) or (Gun and IsValid(ACF_GetAncestor(Gun):GetPhysicsObject()) and ACF_GetAncestor(Gun):GetPhysicsObject():GetVelocity() * 0.2) or Vector()
		if Trace and Trace.HitNormal:LengthSqr() ~= 0 then -- SPROING, not really but
			local Vel = ParentVel:Length() * 0.1
			local Dot = -ParentVel:GetNormalized():Dot(Trace.HitNormal)
			ParentVel = ((ParentVel:GetNormalized() * (1 - Dot) * 3) + (Trace.HitNormal * 1.5)):GetNormalized() * (Vel * math.min(math.max((1 - Dot) * 2,0.25),1))
		end

		if (not util.IsInWorld(ExplosiveData.Origin)) or not (ExplosiveData.ProjMass or ExplosiveData.FragMass) then print("Can't spawn fragments!") return end

		-- The divisor is to "combine" fragments so we can spawn more sane amounts
		local FragMass = ExplosiveData.FragMass or (ExplosiveData.ProjMass - ExplosiveData.ExplosiveMass)
		local Fragments  = math.Clamp(math.floor(((ExplosiveData.ExplosiveMass / FragMass) * ACF.HEFrag) / 8), 2, 255)
		local FragmentPotential = math.max(math.floor((ExplosiveData.ExplosiveMass / FragMass) * ACF.HEFrag), 2)
		local FragmentBoost = (FragmentPotential / Fragments) * 0.5
		print(Fragments .. " frags, " .. FragmentPotential .. " potentially, " .. math.Round(FragmentBoost * 100,1) .. "% boost")

		-- TODO: Turn into a broken sphere of fragments, sent only to props not destroyed but are hittable

		FragData.Owner = ExplosiveData.Inflictor
		FragData.Gun = Gun
		FragData.Filter = Filter
		FragData.Pos = ExplosiveData.Origin - (Bullet and (Bullet.Flight and Bullet.Flight:GetNormalized()) or Vector())

		local BaseFragWeight = FragMass / FragmentPotential
		for _ = 1,Fragments do
			local Caliber = math.Rand(0.5, 1.5) -- Random fragment caliber
			local FragWeight = BaseFragWeight * (Caliber / 1)
			local ProjArea = pi * (Caliber * 0.05) ^ 2
			local FragVel = (((FragEnergy * 5000 / FragWeight) ^ 0.5) / 10)

			FragData.ProjMass = FragWeight * FragmentBoost
			FragData.ProjArea = ProjArea * math.max(1,FragmentBoost / 2)
			FragData.Caliber = Caliber * 0.05
			FragData.Diameter = Caliber * 0.05
			FragData.DragCoef = ProjArea * 0.0001 / FragWeight

			CreateFrag(FragVel,ParentVel,FragData) -- TODO: Works fine, uncomment when done with blast damage
		end
	end

	local function explode(ply)
		local hitpos = ply:GetEyeTrace().HitPos
		ACF.HE({Origin = hitpos,ExplosiveMass = 11,ProjMass = 17,Inflictor = ply},{},ply,ply:GetEyeTrace())
	end
	concommand.Add("acf_explode",explode) -- TODO: REMOVE!!!!

--[[
	-- TODO: Separate this function into multiple chunks, it's absolutely unreadable.
	function ACF.HE(Origin, FillerMass, FragMass, Inflictor, Filter, Gun)
		debugoverlay.Cross(Origin, 15, 15, Color( 255, 255, 255 ), true)
		Filter = Filter or {}

		local Power 	 = FillerMass * ACF.HEPower --Power in KiloJoules of the filler mass of TNT
		local Radius 	 = FillerMass ^ 0.33 * 8 * 39.37 -- Scaling law found on the net, based on 1PSI overpressure from 1 kg of TNT at 15m
		local MaxSphere  = 4 * 3.1415 * (Radius * 2.54) ^ 2 --Surface Area of the sphere at maximum radius
		local Amp 		 = math.min(Power / 2000, 50)
		local Fragments  = math.max(math.floor((FillerMass / FragMass) * ACF.HEFrag), 2)
		local FragWeight = FragMass / Fragments
		local BaseFragV  = (Power * 50000 / FragWeight / Fragments) ^ 0.5
		local Damaged	 = {}
		local Ents 		 = ents.FindInSphere(Origin, Radius)
		local Loop 		 = true -- Find more props to damage whenever a prop dies

		TraceData.filter = Filter
		TraceData.start  = Origin

		util.ScreenShake(Origin, Amp, Amp, Amp / 15, Radius * 10)

		-- We only need to set these once
		Bullet.Owner = Inflictor
		Bullet.Gun   = Gun

		while Loop and Power > 0 do
			Loop = false

			local PowerSpent = 0
			local Damage 	 = {}

			for K, Ent in ipairs(Ents) do -- Find entities to deal damage to
				if not ACF.Check(Ent) then -- Entity is not valid to ACF

					Ents[K] = nil -- Remove from list
					Filter[#Filter + 1] = Ent -- Filter from traces

					continue
				end

				if Damage[Ent] then continue end -- A trace sent towards another prop already hit this one instead, no need to check if we can see it

				if Ent.Exploding then -- Detonate explody things immediately if they're already cooking off
					Ents[K] = nil
					Filter[#Filter + 1] = Ent

					--Ent:Detonate()
					continue
				end

				local IsChar = Ent:IsPlayer() or Ent:IsNPC()
				if IsChar and Ent:Health() <= 0 then
					Ents[K] = nil
					Filter[#Filter + 1] = Ent -- Shouldn't need to filter a dead player but we'll do it just in case

					continue
				end

				local Target = GetRandomPos(Ent, IsChar) -- Try to hit a random spot on the entity
				local Displ	 = Target - Origin

				TraceData.endpos = Origin + Displ:GetNormalized() * (Displ:Length() + 24)

				local TraceRes = ACF.TraceF(TraceData)

				if TraceRes.HitNonWorld then
					Ent = TraceRes.Entity

					if ACF.Check(Ent) then
						if not Ent.Exploding and not Damage[Ent] and not Damaged[Ent] then -- Hit an entity that we haven't already damaged yet (Note: Damaged != Damage)
							local Mul = IsChar and 0.65 or 1 -- Scale down boxes for players/NPCs because the bounding box is way bigger than they actually are

							debugoverlay.Line(Origin, TraceRes.HitPos, 30, Color(0, 255, 0), true) -- Green line for a hit trace
							debugoverlay.BoxAngles(Ent:GetPos(), Ent:OBBMins() * Mul, Ent:OBBMaxs() * Mul, Ent:GetAngles(), 30, Color(255, 0, 0, 1))

							local Pos		= Ent:GetPos()
							local Distance	= Origin:Distance(Pos)
							local Sphere 	= math.max(4 * 3.1415 * (Distance * 2.54) ^ 2, 1) -- Surface Area of the sphere at the range of that prop
							local Area 		= math.min(Ent.ACF.Area / Sphere, 0.5) * MaxSphere -- Project the Area of the prop to the Area of the shadow it projects at the explosion max radius

							Damage[Ent] = {
								Dist  = Distance,
								Displ = Pos - Origin,
								Vec   = (Pos - Origin):GetNormalized(),
								Area  = Area,
								Index = K,
								Trace = TraceRes,
							}

							Ents[K] = nil -- Removed from future damage searches (but may still block LOS)
						end
					else -- If check on new ent fails
						--debugoverlay.Line(Origin, TraceRes.HitPos, 30, Color(255, 0, 0)) -- Red line for a invalid ent

						Ents[K] = nil -- Remove from list
						Filter[#Filter + 1] = Ent -- Filter from traces
					end
				else
					-- Not removed from future damage sweeps so as to provide multiple chances to be hit
					debugoverlay.Line(Origin, TraceRes.HitPos, 30, Color(0, 0, 255)) -- Blue line for a miss
				end
			end

			-- TODO: Add proper fragment support
			-- NOTE: Fragments are flying at several km/s
			for Ent, Table in pairs(Damage) do -- Deal damage to the entities we found
				local AreaFraction 	= Table.Area / MaxSphere
				local PowerFraction = Power * AreaFraction -- How much of the total power goes to that prop
				local Caliber       = math.Rand(0.5, 1) -- Random fragment caliber
				local ProjArea      = math.pi * (Caliber * 0.5) ^ 2
				local FragHit 		= math.floor(Fragments * AreaFraction)
				local FragRes

				Bullet.Caliber  = Caliber
				Bullet.Diameter = Caliber
				Bullet.ProjArea = ProjArea * FragHit
				Bullet.ProjMass = FragWeight * FragHit
				Bullet.Flight   = Table.Displ
				Bullet.Speed    = Bullet.Flight:Length() / ACF.Scale * 0.0254

				local BlastRes = ACF.Damage(Bullet, Table.Trace)
				local Losses   = BlastRes.Loss * 0.5

				if FragHit > 0 then
					local DragCoef = ProjArea * 0.0002 / Bullet.ProjMass

					Bullet.ProjArea = ProjArea
					Bullet.Speed    = ACF.GetRangedSpeed(BaseFragV * 0.0254, DragCoef, Table.Dist) -- NOTE: Assuming BaseFragV is on in/s

					FragRes = ACF.Damage(Bullet, Table.Trace)
					Losses 	= Losses + FragRes.Loss * 0.5
				end

				if BlastRes.Kill or (FragRes and FragRes.Kill) then -- We killed something
					Filter[#Filter + 1] = Ent -- Filter out the dead prop
					Ents[Table.Index]   = nil -- Don't bother looking for it in the future

					local Debris = ACF.HEKill(Ent, Table.Vec, PowerFraction, Origin) -- Make some debris

					for Fireball in pairs(Debris) do
						if IsValid(Fireball) then Filter[#Filter + 1] = Fireball end -- Filter that out too
					end

					Loop = true -- Check for new targets since something died, maybe we'll find something new
				elseif ACF.HEPush then -- Just damaged, not killed, so push on it some
					ACF.KEShove(Ent, Origin, Table.Vec, PowerFraction * 33.3) -- Assuming about 1/30th of the explosive energy goes to propelling the target prop (Power in KJ * 1000 to get J then divided by 33)
				end

				PowerSpent = PowerSpent + PowerFraction * Losses -- Removing the energy spent killing props
				Damaged[Ent] = true -- This entity can no longer recieve damage from this explosion
			end

			Power = math.max(Power - PowerSpent, 0)
		end
	end]]

	ACF_HE = ACF.HE
end -----------------------------------------

do -- Overpressure --------------------------
	ACF.Squishies = ACF.Squishies or {}

	local Squishies = ACF.Squishies

	-- InVehicle and GetVehicle are only for players, we have NPCs too!
	local function GetVehicle(Entity)
		if not IsValid(Entity) then return end

		local Parent = Entity:GetParent()

		if not Parent:IsVehicle() then return end

		return Parent
	end

	local function CanSee(Target, Data)
		local R = ACF.TraceF(Data)

		return R.Entity == Target or not R.Hit or R.Entity == GetVehicle(Target)
	end

	hook.Add("PlayerSpawnedNPC", "ACF Squishies", function(_, Ent)
		Squishies[Ent] = true
	end)

	hook.Add("OnNPCKilled", "ACF Squishies", function(Ent)
		Squishies[Ent] = nil
	end)

	hook.Add("PlayerSpawn", "ACF Squishies", function(Ent)
		Squishies[Ent] = true
	end)

	hook.Add("PostPlayerDeath", "ACF Squishies", function(Ent)
		Squishies[Ent] = nil
	end)

	hook.Add("EntityRemoved", "ACF Squishies", function(Ent)
		Squishies[Ent] = nil
	end)

	function ACF.Overpressure(Origin, Energy, Inflictor, Source, Forward, Angle)
		local Radius = Energy ^ 0.33 * 0.025 * 39.37 -- Radius in meters (Completely arbitrary stuff, scaled to have 120s have a radius of about 20m)
		local Data = { start = Origin, endpos = true, mask = MASK_SHOT }

		if Source then -- Filter out guns
			if Source.BarrelFilter then
				Data.filter = {}

				for K, V in pairs(Source.BarrelFilter) do Data.filter[K] = V end -- Quick copy of gun barrel filter
			else
				Data.filter = { Source }
			end
		end

		util.ScreenShake(Origin, Energy, 1, 0.25, Radius * 3 * 39.37 )

		if Forward and Angle then -- Blast direction and angle are specified
			Angle = math.rad(Angle * 0.5) -- Convert deg to rads

			for V in pairs(Squishies) do
				local Position = V:EyePos()

				if math.acos(Forward:Dot((Position - Origin):GetNormalized())) < Angle then
					local D = Position:Distance(Origin)

					if D / 39.37 <= Radius then

						Data.endpos = Position + VectorRand() * 5

						if CanSee(V, Data) then
							local Damage = Energy * 175000 * (1 / D^3)

							V:TakeDamage(Damage, Inflictor, Source)
						end
					end
				end
			end
		else -- Spherical blast
			for V in pairs(Squishies) do
				local Position = V:EyePos()

				if CanSee(Origin, V) then
					local D = Position:Distance(Origin)

					if D / 39.37 <= Radius then

						Data.endpos = Position + VectorRand() * 5

						if CanSee(V, Data) then
							local Damage = Energy * 150000 * (1 / D^3)

							V:TakeDamage(Damage, Inflictor, Source)
						end
					end
				end
			end
		end
	end
end -----------------------------------------

do -- Deal Damage ---------------------------
	local Network = ACF.Networking

	local function CalcDamage(Bullet, Trace, Volume)
		local Angle   = ACF.GetHitAngle(Trace.HitNormal, Bullet.Flight)
		local HitRes  = {}

		if Bullet.IsTorch then
			return {Damage = math.min(Bullet.TorchDamage or ACF.TorchDamage,Trace.Entity.ACF.MaxHealth * 0.01),Loss = 0,Overkill = 0}
		end

		local Caliber			= Bullet.Diameter * 10
		local BaseArmor			= Trace.Entity.ACF.Armour
		local SlopeFactor		= BaseArmor / Caliber
		local EffectiveArmor	= BaseArmor / math.abs(math.cos(math.rad(Angle)) ^ SlopeFactor)
		local BulletPen			= Bullet:GetPenetration() --RHA Penetration
		local MaxPen			= math.min(BulletPen,EffectiveArmor)

		local Damage			= isnumber(Volume) and Volume or (MaxPen * ((Bullet.Diameter * 0.5) ^ 2) * pi)
		local Loss				= math.Clamp(MaxPen / BulletPen,0,1)

		if Loss == 1 and not Volume then
			local Rico,_ = ACF_CalcRicochet(Bullet, Trace)
			local Ang = 90 * Rico
			if Ang > (Bullet.Ricochet or 60) then
				Damage = Damage * math.max(1 - Rico,0.25)
			end
		end

		HitRes.Damage	= Damage
		HitRes.Loss		= Loss
		HitRes.Overkill	= math.max(BulletPen - MaxPen,0)

		return HitRes
	end

	local function SquishyDamage(Bullet, Trace, Volume)
		local Entity = Trace.Entity
		local Bone   = Trace.HitGroup
		local Armor  = Entity.ACF.Armour
		local Size   = Entity:BoundingRadius()
		local Mass   = Entity.ACF.Mass or Entity:GetPhysicsObject():GetMass()
		local HitRes = {}
		local Damage = 0

		if Bone then
			--This means we hit the head
			if Bone == 1 then
				Entity.ACF.Armour = Mass * 0.02 --Set the skull thickness as a percentage of Squishy weight, this gives us 2mm for a player, about 22mm for an Antlion Guard. Seems about right
				HitRes = CalcDamage(Bullet, Trace, Volume) --This is hard bone, so still sensitive to impact angle
				Damage = HitRes.Damage * 20

				--If we manage to penetrate the skull, then MASSIVE DAMAGE
				if HitRes.Overkill > 0 then
					Entity.ACF.Armour = Size * 0.25 * 0.01 --A quarter the bounding radius seems about right for most critters head size
					HitRes = CalcDamage(Bullet, Trace, Volume)
					Damage = Damage + HitRes.Damage * 100
				end

				Entity.ACF.Armour = Mass * 0.065 --Then to check if we can get out of the other side, 2x skull + 1x brains
				HitRes = CalcDamage(Bullet, Trace, Volume)
				Damage = Damage + HitRes.Damage * 20
			elseif Bone == 0 or Bone == 2 or Bone == 3 then
				--This means we hit the torso. We are assuming body armour/tough exoskeleton/zombie don't give fuck here, so it's tough
				Entity.ACF.Armour = Mass * 0.08 --Set the armour thickness as a percentage of Squishy weight, this gives us 8mm for a player, about 90mm for an Antlion Guard. Seems about right
				HitRes = CalcDamage(Bullet, Trace, Volume) --Armour plate,, so sensitive to impact angle
				Damage = HitRes.Damage * 5

				if HitRes.Overkill > 0 then
					Entity.ACF.Armour = Size * 0.5 * 0.02 --Half the bounding radius seems about right for most critters torso size
					HitRes = CalcDamage(Bullet, Trace, Volume)
					Damage = Damage + HitRes.Damage * 50 --If we penetrate the armour then we get into the important bits inside, so DAMAGE
				end

				Entity.ACF.Armour = Mass * 0.185 --Then to check if we can get out of the other side, 2x armour + 1x guts
				HitRes = CalcDamage(Bullet, Trace, Volume)
			elseif Bone == 4 or Bone == 5 then
				--This means we hit an arm or appendage, so ormal damage, no armour
				Entity.ACF.Armour = Size * 0.2 * 0.02 --A fitht the bounding radius seems about right for most critters appendages
				HitRes = CalcDamage(Bullet, Trace, Volume) --This is flesh, angle doesn't matter
				Damage = HitRes.Damage * 30 --Limbs are somewhat less important
			elseif Bone == 6 or Bone == 7 then
				Entity.ACF.Armour = Size * 0.2 * 0.02 --A fitht the bounding radius seems about right for most critters appendages
				HitRes = CalcDamage(Bullet, Trace, Volume) --This is flesh, angle doesn't matter
				Damage = HitRes.Damage * 30 --Limbs are somewhat less important
			elseif (Bone == 10) then
				--This means we hit a backpack or something
				Entity.ACF.Armour = Size * 0.1 * 0.02 --Arbitrary size, most of the gear carried is pretty small
				HitRes = CalcDamage(Bullet, Trace, Volume) --This is random junk, angle doesn't matter
				Damage = HitRes.Damage * 2 --Damage is going to be fright and shrapnel, nothing much
			else --Just in case we hit something not standard
				Entity.ACF.Armour = Size * 0.2 * 0.02
				HitRes = CalcDamage(Bullet, Trace, Volume)
				Damage = HitRes.Damage * 30
			end
		else --Just in case we hit something not standard
			Entity.ACF.Armour = Size * 0.2 * 0.02
			HitRes = CalcDamage(Bullet, Trace, Volume)
			Damage = HitRes.Damage * 10
		end

		Entity.ACF.Armour = Armor -- Restoring armor

		Entity:TakeDamage(Damage, Bullet.Owner, Bullet.Gun)

		HitRes.Kill = false

		return HitRes
	end

	local function VehicleDamage(Bullet, Trace, Volume)
		local HitRes = CalcDamage(Bullet, Trace, Volume)
		local Entity = Trace.Entity
		local Driver = Entity:GetDriver()

		if IsValid(Driver) then
			Trace.HitGroup = math.Rand(0, 7) -- Hit a random part of the driver
			SquishyDamage(Bullet, Trace) -- Deal direct damage to the driver
		end

		HitRes.Kill = false

		if HitRes.Damage >= Entity.ACF.Health then
			HitRes.Kill = true
		else
			Entity.ACF.Health = Entity.ACF.Health - HitRes.Damage
			Entity.ACF.Armour = Entity.ACF.Armour * (0.5 + Entity.ACF.Health / Entity.ACF.MaxHealth / 2) --Simulating the plate weakening after a hit
		end

		return HitRes
	end

	local function PropDamage(Bullet, Trace, Volume)
		local Entity = Trace.Entity
		local Health = Entity.ACF.Health
		local HitRes = CalcDamage(Bullet, Trace, Volume)

		HitRes.Kill = false

		if HitRes.Damage >= Health then
			HitRes.Kill = true
		else
			Entity.ACF.Health = Health - HitRes.Damage
			Entity.ACF.Armour = math.Clamp(Entity.ACF.MaxArmour * (0.5 + Entity.ACF.Health / Entity.ACF.MaxHealth / 2) ^ 1.7, Entity.ACF.MaxArmour * 0.25, Entity.ACF.MaxArmour) --Simulating the plate weakening after a hit

			Network.Broadcast("ACF_Damage", Entity)
		end

		return HitRes
	end

	ACF.PropDamage = PropDamage

	function ACF.Damage(Bullet, Trace, Volume)
		local Entity = Trace.Entity
		local Type   = ACF.Check(Entity)

		if HookRun("ACF_BulletDamage", Bullet, Trace) == false or Type == false or Bullet.Flight:Length() == math.huge then
			return { -- No damage
				Damage = 0,
				Overkill = 0,
				Loss = 0,
				Kill = false
			}
		end

		if Entity.ACF_OnDamage then -- Use special damage function if target entity has one
			return Entity:ACF_OnDamage(Bullet, Trace, Volume)
		elseif Type == "Prop" then
			return PropDamage(Bullet, Trace, Volume)
		elseif Type == "Vehicle" then
			return VehicleDamage(Bullet, Trace, Volume)
		elseif Type == "Squishy" then
			return SquishyDamage(Bullet, Trace, Volume)
		end
	end

	ACF_Damage = ACF.Damage

	-- This will return an area of the cross section of the center of the hull of the supplied entity as seen from the supplied point
	local function GetCrossSectionalArea(point,ent)
		local ePos = ent:LocalToWorld(ent.OBBCenterOrg or ent:OBBCenter())
		local angToEnt = (ePos - point):GetNormalized():Angle()
		local locSize = ent:OBBMaxs() - ent:OBBMins()
		local locAng = ent:WorldToLocalAngles(angToEnt) -- we're gonna do the funny

		debugoverlay.BoxAngles(ePos,-locSize / 2,locSize / 2,ent:GetAngles(),15,Color(255,127,0,1),false)
		--debugoverlay.BoxAngles(ePos,Vector(0,-x / 2,-y / 2),Vector(0,x / 2,y / 2),ang,15,Color(255,0,0,1),false)

		return (locAng:Right() * locSize):Length() * (locAng:Up() * locSize):Length()
	end
	ACF.GetCrossSectionalArea = GetCrossSectionalArea

	--[[
		BlastData = {
			Origin = Vector(), -- Center of explosion
			Radius = 0, -- Largest distance from the center possible
			Energy = 0, -- Energy at the very center (peak energy)
			MaxArea = 0, The surface area of the radius of the blast sphere
		}

		Entity being calculated against

		The cross section of the hull of the entity (use the handy GetCrossSectionalArea function!)
	]]

	-- This is constant data to be stored locally throughout an instance of BlastDamage being called
	function ACF.GetBlastInfo(ExplosiveData)
		local BlastData = {}
		BlastData.Origin = ExplosiveData.Origin
		local Energy = ExplosiveData.ExplosiveMass * ACF.HEPower
		BlastData.Energy = Energy --Power in KiloJoules of the filler mass of TNT

		local Radius = (Energy ^ (1 / 3)) * 15
		BlastData.Radius = Radius
		BlastData.MaxArea = 4 * pi * (Radius ^ 2) -- Total area of the blast sphere

		BlastData.Owner = ExplosiveData.Owner -- The person/object responsible for this explosion
		BlastData.Gun = ExplosiveData.Gun -- The weapon/object that the made the explosion possible

		return BlastData
	end

	function ACF.BlastDamage(BlastData,Entity,EntPos,CrossSectionalArea)
		local Type = ACF.Check(Entity)
		if HookRun("ACF_BlastDamage", BlastData,Entity) == false or Type == false then
			return {
				Damage = 0,
				Overkill = 0,
				Loss = 0,
				Kill = false
			}
		end

		local dist = math.max(math.min((BlastData.Origin - EntPos):Length(),BlastData.Radius),0.1)

		-- Surface area of the cross section of the sphere at the object position
		local WaveTotalArea = pi * (BlastData.Radius ^ 2) * (dist / BlastData.Radius)

		--print("ENERGY",BlastData.Energy,EnergyFrac)

		-- Find the ratio between the face from the blast sphere to the object's face
		local AreaRatio = math.min(1,WaveTotalArea / CrossSectionalArea)

		--print("AREA RATIO",AreaRatio,CrossSectionalArea,WaveTotalArea)
		--print("Final Energy >>>",EnergyFrac * AreaRatio)

		local dr = dist / BlastData.Radius
		-- A horribly butchered mix of functions to give me something feasible
		local E = BlastData.Energy * math.exp(-((dist * 12.5) / BlastData.Radius)) * (1 - dr)

		local Damage = E * ((WaveTotalArea / BlastData.MaxArea) / CrossSectionalArea) * (WaveTotalArea * 25 * AreaRatio)

		if Type == "Squishy" then
			Entity:TakeDamage(Damage / 4, BlastData.Owner, BlastData.Gun)
			debugoverlay.Text(EntPos,"Damage?? " .. (Damage / 4),15,false)
			print("Applying Squishy " .. (Damage / 4) .. " to " .. tostring(Entity))
		elseif Type == "Vehicle" then
			if IsValid(Entity:GetDriver()) then
				Entity:GetDriver():TakeDamage(Damage / 4, BlastData.Owner, BlastData.Gun)
			end
			local HP = Entity.ACF.Health
			HP = HP - Damage
			Entity.ACF.Health = HP

			if HP <= 0 then
				ACF.HEKill(Entity,(BlastData.Origin - (EntPos + VectorRand(-CrossSectionalArea / 10,CrossSectionalArea / 10))):GetNormalized(),BlastData.Origin,E * 2.5)
			end

			print("Applying Seat " .. Damage .. " to " .. tostring(Entity))
			debugoverlay.Text(EntPos,"Damage?? " .. Damage ,15,false)
		else
			local HP = Entity.ACF.Health
			HP = HP - Damage
			print("Applying Prop " .. Damage .. " to " .. tostring(Entity),Entity.ACF.Health .. " TO " .. HP)

			Entity.ACF.Health = HP

			if HP <= 0 then
				ACF.HEKill(Entity,(BlastData.Origin - (EntPos + VectorRand(-CrossSectionalArea / 10,CrossSectionalArea / 10))):GetNormalized(),BlastData.Origin,E * 2.5)
			end
			--debugoverlay.Text(EntPos,"Damage?? " .. Damage ,15,false)
		end

		return E
	end

	hook.Add("ACF_OnPlayerLoaded", "ACF Render Damage", function(Player)
		for _, Entity in ipairs(ents.GetAll()) do
			local Data = Entity.ACF

			if not Data or Data.Health == Data.MaxHealth then continue end

			Network.Send("ACF_Damage", Player, Entity)
		end
	end)

	Network.CreateSender("ACF_Damage", function(Queue, Entity)
		local Value = math.Round(Entity.ACF.Health / Entity.ACF.MaxHealth, 2)

		if Value == 0 then return end
		if Value ~= Value then return end

		Queue[Entity:EntIndex()] = Value
	end)
end -----------------------------------------

do -- Remove Props ------------------------------
	util.AddNetworkString("ACF_Debris")

	local ValidDebris = ACF.ValidDebris
	local ChildDebris = ACF.ChildDebris
	local Queue       = {}

	local function SendQueue()
		for Entity, Data in pairs(Queue) do
			local JSON = util.TableToJSON(Data)

			net.Start("ACF_Debris")
				net.WriteString(JSON)
			net.SendPVS(Data.Position)

			Queue[Entity] = nil
		end
	end

	local function DebrisNetter(Entity, Normal, Power, CanGib, Ignite)
		if not ACF.GetServerBool("CreateDebris") then return end
		if Queue[Entity] then return end

		local Current = Entity:GetColor()
		local New     = Vector(Current.r, Current.g, Current.b) * math.Rand(0.3, 0.6)

		if not next(Queue) then
			timer.Create("ACF_DebrisQueue", 0, 1, SendQueue)
		end

		Queue[Entity] = {
			Position = Entity:GetPos(),
			Angles   = Entity:GetAngles(),
			Material = Entity:GetMaterial(),
			Model    = Entity:GetModel(),
			Color    = Color(New.x, New.y, New.z, Current.a),
			Normal   = Normal,
			Power    = Power,
			CanGib   = CanGib or nil,
			Ignite   = Ignite or nil,
		}
	end

	function ACF.KillChildProps(Entity, BlastPos, Energy)
		local Explosives = {}
		local Children 	 = ACF_GetAllChildren(Entity)
		local Count		 = 0

		-- do an initial processing pass on children, separating out explodey things to handle last
		for Ent in pairs(Children) do
			Ent.ACF_Killed = true -- mark that it's already processed

			if not ValidDebris[Ent:GetClass()] then
				Children[Ent] = nil -- ignoring stuff like holos, wiremod components, etc.
			else
				Ent:SetParent()

				if Ent.IsExplosive and not Ent.Exploding then
					Explosives[Ent] = true
					Children[Ent] 	= nil
				else
					Count = Count + 1
				end
			end
		end

		-- HE kill the children of this ent, instead of disappearing them by removing parent
		if next(Children) then
			local DebrisChance 	= math.Clamp(ChildDebris / Count, 0, 1)
			local Power 		= Energy / math.min(Count,3)

			for Ent in pairs( Children ) do
				if math.random() < DebrisChance then
					ACF.HEKill(Ent, (Ent:GetPos() - BlastPos):GetNormalized(), Power)
				else
					constraint.RemoveAll(Ent)
					Ent:Remove()
				end
			end
		end

		-- explode stuff last, so we don't re-process all that junk again in a new explosion
		if next(Explosives) then
			for Ent in pairs(Explosives) do
				Ent.Inflictor = Entity.Inflictor

				Ent:Detonate()
			end
		end
	end

	function ACF.HEKill(Entity, Normal, Energy, BlastPos) -- blast pos is an optional world-pos input for flinging away children props more realistically
		-- if it hasn't been processed yet, check for children
		if not Entity.ACF_Killed then
			ACF.KillChildProps(Entity, BlastPos or Entity:GetPos(), Energy)
		end

		local Radius = Entity:BoundingRadius()
		local Debris = {}

		DebrisNetter(Entity, Normal, Energy, false, true)

		if ACF.GetServerBool("CreateFireballs") then
			local Fireballs = math.Clamp(Radius * 0.01, 1, math.max(10 * ACF.GetServerNumber("FireballMult", 1), 1))
			local Min, Max = Entity:OBBMins(), Entity:OBBMaxs()
			local Pos = Entity:GetPos()
			local Ang = Entity:GetAngles()

			for _ = 1, Fireballs do -- should we base this on prop volume?
				local Fireball = ents.Create("acf_debris")

				if not IsValid(Fireball) then break end -- we probably hit edict limit, stop looping

				local Lifetime = math.Rand(5, 15)
				local Offset   = ACF.RandomVector(Min, Max)

				Offset:Rotate(Ang)

				Fireball:SetPos(Pos + Offset)
				Fireball:Spawn()
				Fireball:Ignite(Lifetime)

				timer.Simple(Lifetime, function()
					if not IsValid(Fireball) then return end

					Fireball:Remove()
				end)

				local Phys = Fireball:GetPhysicsObject()

				if IsValid(Phys) then
					Phys:ApplyForceOffset(Normal * Energy / Fireballs, Fireball:GetPos() + VectorRand())
				end

				Debris[Fireball] = true
			end
		end

		constraint.RemoveAll(Entity)
		Entity:Remove()

		return Debris
	end

	function ACF.APKill(Entity, Normal, Power)
		if not IsValid(Entity) then return end -- Somehow this isn't valid anymore
		ACF.KillChildProps(Entity, Entity:GetPos(), Power) -- kill the children of this ent, instead of disappearing them from removing parent

		DebrisNetter(Entity, Normal, Power, true, false)

		constraint.RemoveAll(Entity)
		Entity:Remove()
	end

	ACF_KillChildProps = ACF.KillChildProps
	ACF_HEKill = ACF.HEKill
	ACF_APKill = ACF.APKill
end
