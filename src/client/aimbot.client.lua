-- TODO:
-- 1. Prevent the aimbot from switching targets if the current target is still a valid one 	- Finished
-- 2. Add the ability to choose lock type - whether its head or torso / root 				- Finished
-- 3. Add a miss chance, which is just a random number applied to pitch & yaw that can throw the aim off by a bit so as to not hit every shot
-- 4. Add customizable Field of View, with a visual representation of how large it is
-- 5. Option to not target invisible players/characters
-- 6. Option to not target friends
-- 7. Option to not target players in the same team											- Finished
-- 8. Fix the issue with the aimbot breaking when the target is perpendicular to us
-- 9. Fix the issue with the aimbot breaking after we respawn, likely due to the way exploits execute the scripts	- Finished
-- 10. Option to switch betweeen 3rd person(move mouse instead of camera) and first person aimbot
-- 11. Make the aimbot target the first valid entity from EntiyList, rather than looping through it entirely it should shoot the first valid one(the distance will have to updated every x seconds in the sortingLoop to account for that fact)


-- Checks --

--if getgenv().XTRAimbot then
--	return
--end

repeat
	task.wait()
until game:IsLoaded()


-- Services --

local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput = game:GetService("UserInputService")


-- Variables --

local Camera = workspace.CurrentCamera
local LocalPlayer = PlayersService.LocalPlayer
local LocalTeamName = LocalPlayer.Team.Name
local Character = LocalPlayer.Character or LocalPlayer.CharacterAppearanceLoaded:Wait()
local CharacterHumanoid = Character:WaitForChild("Humanoid")
local CharacterRoot = Character:WaitForChild("HumanoidRootPart")

-- Update local player variables when the player respawns
LocalPlayer.CharacterAdded:Connect(function(character)
	Character = character
	CharacterRoot = character:WaitForChild("HumanoidRootPart")
	CharacterHumanoid = character:WaitForChild("Humanoid")
end)


-- Enums --

local EntityTypes = {
	["Player"] = 1,
	["Bot"] = 2
}

local LockParts = {
	["Head"] = 1,
	["Root"] = 2
}


-- Aimbot Settings --

local Settings = {
	Toggled = true,
	ToggleKey = Enum.KeyCode.F2,

	TargetPlayers = true,
	TargetBots = true,

	PreferPreviousLockOverClosestEntity = true,
	EntityTimeout = 0.5,	-- Decides how long it takes the aimbot, to switch targets after the previous target(assuming above is true), has been lost

	fieldOfView = 30,
	smooth = true,
	smoothEase = 0.4,		-- how long should it take the aimbot to ease into the target

	IgnoreInvisible = true,
	IgnoreFriends = true,
	IgnoreOwnTeam = true,

	TargetSpecifiedTeams = {},	-- target only players with given team names, leave blank to target all teams except our own

	Range = 600,
	LockPart = LockParts.Head
}


-- Validating Settings(Don't modify) --

local targetTeams = false
if #Settings.TargetSpecifiedTeams > 0 then
	targetTeams = true
end


-- EntityList --

local EntityList = {}
local EntityListHelper = {}


-- EntityList - Functions --
do
	local comp = function(entity1, entity2)
		--Check if the distance exceeds the threshold
		local distanceThreshold = 100

		if entity1.Distance > distanceThreshold and entity2.Distance > distanceThreshold then
			-- If both players are past the threshold, compare distances only
			return entity1.Distance < entity2.Distance
		elseif entity1.Distance > distanceThreshold then
			-- If only player A is past the threshold, prioritize player B
			return false
		elseif entity2.Distance > distanceThreshold then
			-- If only player B is past the threshold, prioritize player A
			return true
		end

		-- If neither player is past the threshold, compare health
		if entity1.Humanoid.Health < entity2.Humanoid.Health then
			return true
		elseif entity1.Humanoid.Health > entity2.Humanoid.Health then
			return false
		end

		-- If health is the same, compare distances
		return entity1.Distance < entity2.Distance
	end

	function EntityListHelper.SortEntityList()
		table.sort(EntityList, comp)
	end

	function EntityListHelper.AddEntity(entityType, character: Model, root, hum, head, teamName)
		local root = root or character:FindFirstChild("HumanoidRootPart")
		local hum = hum or character:FindFirstChildOfClass("Humanoid")
		local head = head or character:FindFirstChild("Head")
		local teamName = teamName or "Neutral"

		if not root or not hum or not head then
			print("Failed to Add Entity - No root / humanoid / head")
			return false
		end

		local entity = {
			EntityType = entityType,
			Character = character,
			Humanoid = hum,
			HumanoidRootPart = root,
			Head = head,
			-- Friends = {}
			Team = teamName,
			Distance = math.huge
		}

		table.insert(EntityList, entity)
		EntityListHelper.SortEntityList()
	end

	function EntityListHelper.RemoveEntity(character: Model)
		for i, entity in ipairs(EntityList) do
			if entity.Character == character then -- Comparing instances instead of character name because it might remove the wrong one if they have the same name
				table.remove(EntityList, i)
				print("Removed from table: " .. entity.Character.Name)
				table.sort(EntityList, comp)
				break
			end
		end
	end

	function EntityListHelper.SearchForEntity(character: Model)
		for i, entity in ipairs(EntityList) do
			if entity.Character == character then
				return i
			end
		end
		return false
	end

	function EntityListHelper.IsPlayer(character: Model)
		if PlayersService:GetPlayerFromCharacter(character) then
			return true
		end

		return false
	end

	function EntityListHelper.GetEntityType(entityCharacter)
		local entityType = EntityTypes.Bot
		if EntityListHelper.IsPlayer(entityCharacter) then
			if entityCharacter.Name == LocalPlayer.Name then
				return false
			end

			entityType = EntityTypes.Player
		end

		return entityType
	end

	function EntityListHelper.HandleTeamChange(player, character)
		local entityIndex = EntityListHelper.SearchForEntity(character)
		if not entityIndex then
			return false
		end

		if player.Team then
			EntityList[entityIndex].Team = player.Team.Name
		else
			EntityList[entityIndex].Team = "Neutral"
		end
	end

	function EntityListHelper.AddEntities()
		for _, humanoid in ipairs(workspace:GetDescendants()) do
			if humanoid.ClassName ~= "Humanoid" then
				continue
			end

			local entityCharacter = humanoid.Parent

			local root = entityCharacter:FindFirstChild("HumanoidRootPart")
			local head = entityCharacter:FindFirstChild("Head")
			if not root or not head then
				continue
			end

			local teamName = "Neutral"
			local teamChangedSignal
			local entityType = EntityListHelper.GetEntityType(entityCharacter)
			if not entityType then
				continue
			end

			if entityType == EntityTypes.Player then
				local player = PlayersService:GetPlayerFromCharacter(entityCharacter)
				if player.Team then
					teamName = player.Team.Name
				end

				teamChangedSignal = player:GetPropertyChangedSignal("Team"):Connect(function()
					EntityListHelper.HandleTeamChange(player, entityCharacter)
					print("Team Changed")
				end)
			end

			EntityListHelper.AddEntity(entityType, entityCharacter, root, humanoid, head, teamName)
			print("Added entity: " .. entityCharacter.Name .. " Type: " .. tostring(entityType) .. " Team: " .. teamName)

			humanoid.Died:Connect(function()
				EntityListHelper.RemoveEntity(entityCharacter)

				if teamChangedSignal then
					teamChangedSignal:Disconnect()
				end
			end)
		end
	end

	function EntityListHelper.AddEntityOnJoin()
		workspace.DescendantAdded:Connect(function(humanoid)
			if humanoid.ClassName ~= "Humanoid" then
				return false
			end

			local entityCharacter = humanoid.Parent

			local root = entityCharacter:FindFirstChild("HumanoidRootPart")
			local head = entityCharacter:FindFirstChild("Head")
			if not root or not head then
				return false
			end

			local teamName = "Neutral"
			local teamChangedSignal
			local entityType = EntityListHelper.GetEntityType(entityCharacter)
			if not entityType then
				return false
			end

			if entityType == EntityTypes.Player then
				local player = PlayersService:GetPlayerFromCharacter(entityCharacter)
				if player.Team then
					teamName = player.Team.Name
				end

				teamChangedSignal = player:GetPropertyChangedSignal("Team"):Connect(function()
					EntityListHelper.HandleTeamChange(player, entityCharacter)
					print("Team Changed")
				end)
			end

			EntityListHelper.AddEntity(entityType, entityCharacter, root, humanoid, head, teamName)
			print("Added entity: " .. entityCharacter.Name .. " Type: " .. tostring(entityType) .. " Team: " .. teamName)

			humanoid.Died:Connect(function()
				EntityListHelper.RemoveEntity(entityCharacter)

				if teamChangedSignal then
					teamChangedSignal:Disconnect()
				end
			end)
		end)
	end
end


-- Aimbot - Functions --

local function GetDistance(position1: Vector3, position2: Vector3)
	return (position1 - position2).Magnitude
end

local function IsInFOV()

end

local function IsVisible(playerCharacter, bodyPart: Instance, range: number)
	-- local _, withinScreen = Camera:WorldToViewportPoint(bodyPart.Position)	-- not reliable, fails randomly, use FOV instead
	-- if withinScreen then
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { playerCharacter }
		params.FilterType = Enum.RaycastFilterType.Exclude

		local raycast = workspace:Raycast(Camera.CFrame.Position, (bodyPart.Position - Camera.CFrame.Position).Unit * range * 1.1, params)
		if raycast and raycast.Instance:IsDescendantOf(bodyPart.Parent) then
			return raycast
		end
	-- end

	return false
end

local function IsImmortal(humanoid: Humanoid, character: Model)
	if not humanoid or humanoid.MaxHealth >= math.huge then
		return true
	end

	for _, forcefield in ipairs(character:GetChildren()) do		-- I put GetChildren() here for performance reasons, but some games might keep the forcefield in root and similar, in that case use GetDescendants()
		if forcefield.ClassName == "ForceField" then
			return true
		end
	end

	return false
end

local function IsEnemyTeam(entity)
	if not targetTeams then
		-- print("Target Teams is not set")
		if LocalTeamName ~= entity.Team then
			-- print("Enemy Team")
			return true
		end
		-- print("Friendly team")
		return false
	end
	
	-- print("Target teams is set")
	for _, targetTeamName in ipairs(Settings.TargetSpecifiedTeams) do
		if entity.Team == targetTeamName then
			return true
		end
	end
	
	return false
end

local function IsValidTarget(entity, previousDistance: number, playerCharacter: Model, playerRoot: Instance, targetBodyPartName: StringValue, maxRange: number)
	if not Settings.TargetPlayers then
		if entity.EntityType == EntityTypes.Player then
			return false
		end
	end

	if not Settings.TargetBots then
		if entity.EntityType == EntityTypes.Bot then
			return false
		end
	end

	if not entity.HumanoidRootPart or not entity.Humanoid then
		return false
	end

	entity.Distance = GetDistance(playerRoot.Position, entity.HumanoidRootPart.Position)

	if entity.Distance > maxRange then
		return false
	end

	if entity.Humanoid.Health <= 0 then
		return false
	end

	if not IsEnemyTeam(entity) then
		return false
	end

	if not IsVisible(playerCharacter, entity[targetBodyPartName], Settings.Range) then
		return false
	end

	if IsImmortal(entity.Humanoid, entity.Character) then
		return false
	end

	if entity.Distance < previousDistance then
		return entity
	end
end

local currentTarget
local function GetClosestEntity(playerCharacter: Model, playerRoot: Instance, targetBodyPartName: StringValue, maxRange: number)
	local closestDistance = math.huge
	local closestEntity
	local currentTargetStillValid = false

	if Settings.PreferPreviousLockOverClosestEntity then
		if currentTarget then
			if IsValidTarget(currentTarget, closestDistance, playerCharacter, playerRoot, targetBodyPartName, maxRange) then
				currentTargetStillValid = true
				closestEntity = currentTarget
			else
				-- Wait a bit and check if hes valid again in order to account for someone briefly blocking our vision
				task.wait(Settings.EntityTimeout)
				if IsValidTarget(currentTarget, closestDistance, playerCharacter, playerRoot, targetBodyPartName, maxRange) then
					currentTargetStillValid = true
					closestEntity = currentTarget
				end
			end
		end
	end

	if not currentTargetStillValid then
		for _, entity in ipairs(EntityList) do
			local validEntity = IsValidTarget(entity, closestDistance, playerCharacter, playerRoot, targetBodyPartName, maxRange)
			if validEntity then
				closestEntity = validEntity
				closestDistance = entity.Distance
				currentTarget = closestEntity
			end
		end
	end

	return closestEntity
end

local function CalculateAngles(localCharacter, entity, targetBodyPartPosition)
	local heightDifference = targetBodyPartPosition.Y - localCharacter.Head.Position.Y
	local slope = GetDistance(localCharacter.Head.Position, targetBodyPartPosition)
	
	local xDistance = localCharacter.HumanoidRootPart.Position.X - entity.HumanoidRootPart.Position.X
	local zDistance = localCharacter.HumanoidRootPart.Position.Z - entity.HumanoidRootPart.Position.Z
	
	local pitch, yaw = math.asin(heightDifference / slope), math.atan2(xDistance, zDistance)
	
	return Vector2.new(yaw, pitch)
end

local function EaseCameraToAngle(target: Vector2, origin: Vector3, ease: number)
	local pitchDiff = target.Y - origin.Y
	local yawDiff = target.X - origin.X

	--print("Current Yaw: ", math.deg(currYaw))
	--print("Yaw Target: ", math.deg(yaw))
	--print("Yaw Difference: ", math.deg(yawDiff))

	Camera.CFrame = CFrame.fromOrientation(origin.Y + pitchDiff * ease, origin.X + yawDiff * ease, origin.Z)
end

local function SetCameraAngle(target: Vector2, origin: Vector3, smooth: boolean, smoothEase: number)
	if smooth then
		EaseCameraToAngle(target, origin, smoothEase)
	else
		Camera.CFrame = CFrame.fromOrientation(target.Y, target.X, origin.Z)
	end
end

local function AimAt(playerCharacter, entity, targetBodyPartPosition)
	local setAngles = CalculateAngles(playerCharacter, entity, targetBodyPartPosition)
	local currPitch, currYaw, currDepth = Camera.CFrame:ToOrientation()

	-- During normal gameplay we cant aim above or below 80 degrees, if we do, every junk AC will detect us, so we run a check here.
	if math.deg(setAngles.Y) >= -80 and math.deg(setAngles.Y) <= 80 and math.deg(setAngles.X) >= -180 and math.deg(setAngles.X) <= 180 then
		SetCameraAngle(setAngles, Vector3.new(currYaw, currPitch, currDepth), Settings.smooth, Settings.smoothEase)
	end
end

local function TargetTimeout()
	task.wait(Settings.EntityTimeout)
	if not currentTarget then
		print("Conditions not met")
		return false
	end

	print("current target set to nil")
	currentTarget = nil
end

EntityListHelper.AddEntities()
EntityListHelper.AddEntityOnJoin()

local RMBDown = false
local RMBBegin
local RMBEnd
local aimbot
local sortingLoop
local targetTimeout

local function RunAimbot()
	if RMBDown and Character and CharacterHumanoid and CharacterHumanoid.Health > 0 then
		local targetBodyPart = "Head"
		if Settings.LockPart == LockParts.Root then
			targetBodyPart = "HumanoidRootPart"
		end

		local closestEntity = GetClosestEntity(Character, CharacterRoot, targetBodyPart, Settings.Range)
		if closestEntity then
			AimAt(Character, closestEntity, closestEntity[targetBodyPart].Position)
			--print(closestEntity.Character.Name)
		end
	end
end

local function Run()
	aimbot = RunService.Heartbeat:Connect(RunAimbot)

	RMBBegin = UserInput.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			RMBDown = true
			print("RMBDown")

			if targetTimeout then
				task.cancel(targetTimeout)
			end
		end
	end)

	RMBEnd = UserInput.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			RMBDown = false

			-- Start a timer responsible for switching targets every time we let go of RMB
			targetTimeout = task.spawn(TargetTimeout)
		end
	end)

	-- Need to sort every x seconds to account for distance updating, as static periods can lead to inaccurate distances, disrupting target selection.
	-- Running it in a GetClosestEntity() loop with distance updating is possible but poor performance-wise. Running it here to essentially sacrifice ideal target selection for better performance.
	sortingLoop = task.spawn(function()
		while task.wait(5) do
			EntityListHelper.SortEntityList()

			for i, entity in pairs(EntityList) do
				print(i, entity.Character.Name, entity.Humanoid.Health, entity.Distance)
			end
		end
	end)
end

local function Stop()
	aimbot:Disconnect()
	RMBBegin:Disconnect()
	RMBEnd:Disconnect()
	if targetTimeout then
		task.cancel(targetTimeout)
	end
	task.cancel(sortingLoop)
end

if Settings.Toggled then
	Run()
end

UserInput.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode ~= Settings.ToggleKey then
			return false
		end

		Settings.Toggled = not Settings.Toggled
		if not Settings.Toggled and aimbot then
			Stop()
		else
			Run()
		end
	end
end)