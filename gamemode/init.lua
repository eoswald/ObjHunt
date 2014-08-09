AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

resource.AddFile("sound/taunts/jihad.wav")
resource.AddFile( "sound/objhunt/iwillkillyou2.wav" )

function GM:PlayerInitialSpawn( ply )
	ply:SetTeam( TEAM_SPECTATOR )
	player_manager.SetPlayerClass( ply, "player_spectator" )
end

-- [[ Class Selection ]] --
function GM:ShowHelp( ply ) -- This hook is called everytime F1 is pressed.
	net.Start( "Class Selection" )
		-- Just used as a hook
	net.Send( ply )
end

net.Receive("Class Selection", function( len, ply )
	local chosen = net.ReadUInt(32)
	local playerTable = {}

	if chosen == ply:Team() then
		ply:ChatPrint( "You are already on that team." )
		return end
	if chosen == TEAM_SPECTATOR then
		player_manager.SetPlayerClass( ply, "player_spectator" )
	end

	playerTable[ TEAM_PROPS ] = team.NumPlayers( TEAM_PROPS )
	playerTable[ TEAM_HUNTERS ] = team.NumPlayers( TEAM_HUNTERS )
	playerTable[ TEAM_SPECTATOR ] = team.NumPlayers( TEAM_SPECTATOR )
	playerTable[ ply:Team() ] = playerTable[ ply:Team() ] - 1

	if math.abs( playerTable[ TEAM_PROPS ] - playerTable[ TEAM_HUNTERS ] ) >= MAX_TEAM_NUMBER_DIFFERENCE then
		if playerTable[ chosen ] == math.max( playerTable[ TEAM_PROPS ], playerTable[ TEAM_HUNTERS ] ) then
			ply:ChatPrint( "Sorry, that team is currently full." )
			return end
	end

	ply:SetTeam( chosen )
	if( chosen == TEAM_PROPS ) then
		player_manager.SetPlayerClass( ply, "player_prop" )
	elseif( chosen == TEAM_HUNTERS ) then
		player_manager.SetPlayerClass( ply, "player_hunter" )
	end

	RemovePlayerProp( ply )
	ply:KillSilent()
	ply:Spawn()
end )

-- [[ Taunts ]] --
function GM:ShowSpare1( ply )
	net.Start( "Taunt Selection" )
		-- Just used as a hook
	net.Send( ply )
end

net.Receive( "Taunt Selection", function( len, ply )
	local taunt = net.ReadString()
	-- random pitch sounds == lol
	-- ply:EmitSound( taunt, 70, math.random()*255 )
	ply:EmitSound( taunt, 70 )
end )


function GM:PlayerSetModel( ply )
	class = player_manager.GetPlayerClass( ply )
	if( class == "player_hunter" ) then
		ply:SetModel( TEAM_HUNTERS_DEFAULT_MODEL )

		-- default
		ply:SetViewOffset( Vector(0,0,64) )
	elseif( class == "player_prop" ) then
		ply:SetModel( TEAM_PROPS_DEFAULT_MODEL )

		-- this fixes ent culling when head in ceiling
		-- should be based on default hit box!
		ply:SetViewOffset( Vector(0,0,35) )
	else
		return
	end
end

function GM:PlayerShouldTakeDamage( victim, attacker )
	-- props cannot take fall damage
	if( victim:Team() == TEAM_PROPS && attacker:GetClass() == "worldspawn" ) then
		return false
	end

	-- no friendly fire
	if( attacker:IsPlayer() ) then
		if( victim:Team() == attacker:Team() && victim != attacker ) then
			return false
		end
	end

	return true
end

hook.Add( "EntityTakeDamage", "damage the correct ent", function( target, dmginfo )
	local attacker = dmginfo:GetAttacker()
	-- since player_prop_ent isn't in USABLE_PROP_ENTS this is sufficient logic to prevent
	-- player owned props from getting hurt
	if( !target:IsPlayer() && table.HasValue( USABLE_PROP_ENTITIES, target:GetClass() ) ) then
		if(attacker:IsPlayer()) then
			attacker:TakeDamage(dmginfo:GetDamage(),attacker,target)
		end
	end
end )

--[[ All network strings should be precached HERE ]]--
hook.Add( "Initialize", "Precache all network strings", function()
	util.AddNetworkString( "Class Selection" )
	util.AddNetworkString( "Taunt Selection" )
	util.AddNetworkString( "Map Time" )
	util.AddNetworkString( "Round Update" )
	util.AddNetworkString( "Prop Update" )
	util.AddNetworkString( "Reset Prop" )
	util.AddNetworkString( "Selected Prop" )
	util.AddNetworkString( "Prop Angle Lock" )
	util.AddNetworkString( "Prop Angle Lock BROADCAST" )
	util.AddNetworkString( "Prop Angle Snap" )
	util.AddNetworkString( "Prop Angle Snap BROADCAST" )
	util.AddNetworkString( "Hunter Release Sound" )
end )

--[[ Map Time ]]--
hook.Add( "Initialize", "Set Map Time", function()
	mapStartTime = os.time()
end )

hook.Add( "PlayerInitialSpawn", "Send Map Time To New Player", function( ply )
	local toSend = ( mapStartTime || os.time() )
	net.Start( "Map Time" )
		net.WriteUInt( toSend, 32 )
	net.Send( ply )
end )

--[[ sets the players prop, run PlayerCanBeEnt before using this ]]--
function SetPlayerProp( ply, ent, scale, hbMin, hbMax )

	local tHitboxMin, tHitboxMax
	if( !hbMin || !hbMax ) then
		tHitboxMin, tHitboxMax = ent:GetHitBoxBounds( 0, 0 )
		if( !tHitboxMin || !tHitboxMax ) then return false, "Invalid Hull" end
	else
		tHitboxMin = hbMin
		tHitboxMax = hbMax
	end

	-- scaling
	ply:GetProp():SetModelScale( scale, 0)


	ply:GetProp():SetModel( ent:GetModel() )
	ply:GetProp():SetSkin( ent:GetSkin() )
	ply:GetProp():SetSolid( SOLID_VPHYSICS )
	ply:GetProp():SetAngles( ply:GetAngles() )

	-- we round to reduce getting stuck
	tHitboxMin = Vector( math.Round(tHitboxMin.x),math.Round(tHitboxMin.y),math.Round(tHitboxMin.z) )
	tHitboxMax = Vector( math.Round(tHitboxMax.x),math.Round(tHitboxMax.y),math.Round(tHitboxMax.z) )

	ply:SetHull( tHitboxMin, tHitboxMax )
	ply:SetHullDuck( tHitboxMin, tHitboxMax )
	local tHeight = tHitboxMax.z-tHitboxMin.z

	-- match the view offset for calcviewing to the height
	ply:SetViewOffset( Vector(0,0,tHeight) )

	-- scale steps to prop size
	ply:SetStepSize( math.Round( 4+(tHeight)/4 ) )

	-- give bigger props a bonus for being big
	ply:SetJumpPower( 200 + math.sqrt(tHeight) )

	ply.lastPropChange = os.time()

	-- Update the player's mass to be something more reasonable to the prop
	local phys = ent:GetPhysicsObject()
	if IsValid(ent) and phys:IsValid() then
		ply:GetPhysicsObject():SetMass(phys:GetMass())
		-- vphysics
		local vPhysMesh = ent:GetPhysicsObject():GetMeshConvexes()
		ply:GetProp():PhysicsInitMultiConvex( vPhysMesh )
	else
		-- Entity doesn't have a physics object so calculate mass
		local density = PROP_DEFAULT_DENSITY
		local volume = (tHitboxMax.x-tHitboxMin.x)*(tHitboxMax.y-tHitboxMin.y)*(tHitboxMax.z-tHitboxMin.z)
		local mass = volume * density

		mass = math.min(100, mass)
		mass = math.max(0, mass)

		ply:GetPhysicsObject():SetMass(mass)
	end

	net.Start( "Prop Update" )
		net.WriteVector( tHitboxMax )
		net.WriteVector( tHitboxMin )
	net.Send( ply )

end

--[[ When a player presses +use on a prop ]]--
net.Receive( "Selected Prop", function( len, ply )
	local ent = net.ReadEntity()

	local tHitboxMin, tHitboxMax = ply:GetProp():GetHitBoxBounds( 0, 0 )
	if( !playerCanBeEnt( ply, ent) ) then return end
	local oldHP = ply:GetProp().health
	SetPlayerProp( ply, ent, PROP_CHOSEN_SCALE )
	ply:GetProp().health = oldHP
end )

--[[ When a player on team_props spawns ]]--
hook.Add( "PlayerSpawn", "Set ObjHunt model", function ( ply )
	--ply:SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
	-- default prop should be able to step wherever
	ply:SetStepSize( 20 )
	ply:SetNotSolid( false )
	if( ply:Team() == TEAM_PROPS ) then
		-- make the player invisible
		ply:SetRenderMode( RENDERMODE_TRANSALPHA )
		ply:SetColor( Color(0,0,0,0) )
		ply:SetBloodColor( DONT_BLEED )

		timer.Simple( 0.5, function()
			ply:SetProp( ents.Create("player_prop_ent") )
			ply:GetProp():Spawn()
			ply:GetProp():SetOwner( ply )
			-- custom initial hb
			SetPlayerProp( ply, ply:GetProp(), PROP_DEFAULT_SCALE, PROP_DEFAULT_HB_MIN, PROP_DEFAULT_HB_MAX )
		end )

	elseif( ply:Team() == TEAM_HUNTERS ) then
		ply:SetRenderMode( RENDERMODE_NORMAL )
		ply:SetColor( Color(255,255,255,255) )
	end

end )

--[[ When a player wants to lock world angles on their prop ]]--
net.Receive( "Prop Angle Lock", function( len, ply )
	local lockStatus = net.ReadBit()
	local propAngle = net.ReadAngle()
	-- this is literally retarded
	if( lockStatus == 1 ) then
		lockStatus = true
	else
		lockStatus = false
	end

	net.Start( "Prop Angle Lock BROADCAST" )
		net.WriteEntity( ply )
		net.WriteBit( lockStatus )
		net.WriteAngle( propAngle )
	net.Broadcast()
end )

--[[ When a player wants toggle world angle snapping on their prop ]]--
net.Receive( "Prop Angle Snap", function( len, ply )
	local snapStatus = net.ReadBit()
	-- this is literally retarded
	if( snapStatus == 1 ) then
		snapStatus = true
	else
		snapStatus = false
	end

	net.Start( "Prop Angle Snap BROADCAST" )
		net.WriteEntity( ply )
		net.WriteBit( snapStatus )
	net.Broadcast()
end )

hook.Add( "PlayerDisconnected", "Remove ent prop on dc", function( ply )
	RemovePlayerProp( ply )
end )

hook.Add( "PlayerDeath", "Remove ent prop on death", function( ply )
	RemovePlayerProp( ply )
	local ragdoll = ply:GetRagdollEntity()
	SafeRemoveEntityDelayed( ragdoll, 5 )
end )

--[[ remove the ent prop ]]--
function RemovePlayerProp( ply )
	if( ply.GetProp && IsValid( ply:GetProp() ) ) then
		ply:GetProp():Remove()
		ply:SetProp( nil )
	end
	ply:ResetHull()
	net.Start( "Reset Prop" )
		-- empty, just used for the hook
	net.Send( ply )
end

function GM:PlayerSelectSpawn( ply )
	local spawns = team.GetSpawnPoints( ply:Team() )
	if( !spawns ) then return false end

    local ret, _ = table.Random( spawns )
    return ret
end
