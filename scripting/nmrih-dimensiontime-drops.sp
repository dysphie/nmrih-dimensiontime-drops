#include <sdktools>
#include <sdkhooks>

#define MAX_POINTCAP_LVL 3
#define MAX_MAXHEALTH_LVL 3

#define MAX_ECO_PLAYERS 8
#define MAXENTITIES 2048
#define EF_ITEM_BLINK 0x100
#define INVALID_ECONOMY_ID -1

char SND_PICKUP[][] = {
	"player/clothes_generic_foley_01.wav",
	"player/clothes_generic_foley_02.wav",
	"player/clothes_generic_foley_03.wav",
	"player/clothes_generic_foley_04.wav",
	"player/clothes_generic_foley_05.wav"
}

#define MDL_MONEYBUNDLE "models/props/junk/money_bundle02.mdl"
#define MDL_SUITCASE "models/props_c17/briefcase001a.mdl"
#define MDL_POLICEVEST "models/items/vest/police_vest.mdl"
#define MDL_SHOE "models/props_junk/shoe001a.mdl"
#define MDL_HEALTHVIAL "models/healthvial.mdl"

#define IN_UNLOAD 0x400000

public Plugin myinfo = {
    name        = "nmo_dimension_time Droppable Cash/Perks",
    author      = "Dysphie",
    description = "Allows cash and perks to be unequipped and dropped",
    version     = "0.1.0",
    url         = ""
};

int healthDisplay[MAX_ECO_PLAYERS] = {INVALID_ENT_REFERENCE, ...};
int pointPerkMgr[MAX_ECO_PLAYERS] = {INVALID_ENT_REFERENCE, ...};
int pointCounter[MAX_ECO_PLAYERS] = {INVALID_ENT_REFERENCE, ...};

bool lateloaded;
bool validMap;

// TODO: Store in targetname instead?
int entData[MAXENTITIES+1]; // Holds money bundle value and armor piece charge

ConVar cvItemDespawn;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateloaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases")
	LoadTranslations("dimension-time-drops.phrases");

	cvItemDespawn = CreateConVar("dim_item_despawn_time", "50", 
		"Dropped perks and cash will despawn after this many seconds");

	HookEvent("nmrih_reset_map", Event_ResetMap);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);

	RegAdminCmd("sm_dim_giveall", Command_Impulse, ADMFLAG_CHEATS);
	RegAdminCmd("sm_dim_stats", Command_Overview, ADMFLAG_CHEATS);
	RegAdminCmd("sm_dim_dropall", Command_DropAll, ADMFLAG_CHEATS);

	RegConsoleCmd("sm_dim", Command_Dimension);

	// fixme: autoexecconfig
}

public Action Command_DropAll(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "%t", "sm_dim_dropall Usage");
		return Plugin_Handled;
	}

	char arg[256];
	GetCmdArg(1, arg, sizeof(arg));

	int target = FindTarget(client, arg, .immunity=false);
	if (target == -1)
		return Plugin_Handled;
	
	DropAll(target, true);
	return Plugin_Handled;
}

void DropAll(int client, bool preserved=false)
{
	// Point upgrades are preserved thru respawns
	// So don't get rid of them unless specified
	if (preserved)
	{
		int id = GetEconomyID(client);
		if (id != INVALID_ECONOMY_ID)
		{
			int ppLvl = PointCapLevel_Get(id)
			for (int i; i < ppLvl; i++)
				DropPointsPerk(client, id);

			int points = GetClientPoints(id);
			if (points > 0)
				DropCash(client, id, points);
		}	
	}

	int hpLvl = MaxHealthLevel_Get(client);
	for (int i; i < hpLvl; i++)
		DropHealthPerk(client);

	int armor = GetClientArmor(client);
	if (armor > 0)
		DropArmor(client, armor);

	if (ClientHasBoots(client))
		DropBoots(client);
}

int MenuHandler_DropPoints(Menu menu, MenuAction menuaction, int param1, int param2)
{
	if (menuaction == MenuAction_End)
		delete menu;

	else if (menuaction == MenuAction_Cancel && param2 == MenuCancel_ExitBack) 
		ShowMenu_Home(param1);

	else if (menuaction == MenuAction_Select)
	{
		int id = GetEconomyID(param1);
		if (id != INVALID_ECONOMY_ID)
		{
			char selection[5];
			menu.GetItem(param2, selection, sizeof(selection));
			int amount = StringToInt(selection);

			if (GetClientPoints(id) >= amount)
			{
				DropCash(param1, id, amount);
				ShowMenu_DropPoints(param1);
				return 0;
			}
		}

		ReplyToCommand(param1, "%t", "Points No Longer Owned");
	}
	return 0;
}

void ShowMenu_DropUpgrade(int client)
{
	Menu menu = new Menu(MenuHandler_DropUpgrade);

	char fmt[2048];

	menu.SetTitle("%T", "Drop Upgrade", client);
	int id = GetEconomyID(client);
	if (id != INVALID_ECONOMY_ID)
	{
		int pointLvl = PointCapLevel_Get(id);
		if (pointLvl > 0)
		{
			FormatEx(fmt, sizeof(fmt), "%T", "Increased Points", client, pointLvl);
			menu.AddItem("p", fmt);
		}
	}

	int hpLvl = MaxHealthLevel_Get(client);
	if (hpLvl > 0)
	{
		FormatEx(fmt, sizeof(fmt), "%T", "Increased Health", client, hpLvl);
		menu.AddItem("h", fmt);
	}

	if (GetClientArmor(client) > 0)
	{
		FormatEx(fmt, sizeof(fmt), "%T", "Police Vest", client);
		menu.AddItem("a", fmt);
	}
	
	if (ClientHasBoots(client))
	{
		FormatEx(fmt, sizeof(fmt), "%T", "Speed Boots", client);
		menu.AddItem("b", fmt);
	}

	if (menu.ItemCount < 1)
	{
		FormatEx(fmt, sizeof(fmt), "%T", "No Upgrades", client);
		menu.AddItem("", fmt, ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void ShowMenu_Home(int client)
{
	Menu menu = new Menu(MenuHandler_Home);
	menu.SetTitle("%T", "Inventory Actions", client);

	char fmt[2048];
	FormatEx(fmt, sizeof(fmt), "%T", "Drop Points", client);
	menu.AddItem("dp", fmt);

	FormatEx(fmt, sizeof(fmt), "%T", "Drop Upgrade", client);
	menu.AddItem("du", fmt);

	menu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Home(Menu menu, MenuAction menuaction, int param1, int param2)
{
	if (menuaction == MenuAction_End)
		delete menu;

	else if (menuaction == MenuAction_Select)
	{
		char selection[8];
		menu.GetItem(param2, selection, sizeof(selection));

		if (StrEqual(selection, "dp"))
			ShowMenu_DropPoints(param1);

		else if (StrEqual(selection, "du"))
			ShowMenu_DropUpgrade(param1);
	}
}

void ShowMenu_DropPoints(int client)
{
	// TODO: Optimize?
	int OPTIONS[] = {1, 2, 3, 5, 10, 15, 30};

	Menu menu = new Menu(MenuHandler_DropPoints);
	menu.SetTitle("%T", "Drop Points", client);

	char item[5], itemDisplay[64];

	int id = GetEconomyID(client);
	if (id != INVALID_ECONOMY_ID)
	{
		int points = GetClientPoints(id);

		for (int i; i < sizeof(OPTIONS); i++)
		{
			if (OPTIONS[i] > points)
				break;

			IntToString(OPTIONS[i], item, sizeof(item));
			FormatEx(itemDisplay, sizeof(itemDisplay), "$%d", OPTIONS[i]);
			menu.AddItem(item, itemDisplay);
		}
	}

	if (menu.ItemCount < 1)
	{
		FormatEx(itemDisplay, sizeof(itemDisplay), "%T", "No Points", client);
		menu.AddItem("", itemDisplay, ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_DropUpgrade(Menu menu, MenuAction menuaction, int param1, int param2)
{
	if (menuaction == MenuAction_End)
		delete menu;

	else if (menuaction == MenuAction_Cancel && param2 == MenuCancel_ExitBack) 
		ShowMenu_Home(param1);

	else if (menuaction == MenuAction_Select)
	{
		char selection[2];
		menu.GetItem(param2, selection, sizeof(selection));
		switch (selection[0])
		{
			case 'p':
			{
				int id = GetEconomyID(param1);
				if (id == INVALID_ECONOMY_ID || PointCapLevel_Get(id) <= 0)
					PrintToChat(param1, "%t", "Upgrade No Longer Owned");
				else
					DropPointsPerk(param1, id);
			}
			case 'h':
			{
				int id = GetEconomyID(param1);
				if (id == INVALID_ECONOMY_ID || MaxHealthLevel_Get(param1) < 1)
					PrintToChat(param1, "%t", "Upgrade No Longer Owned");
				else
					DropHealthPerk(param1);
			}
			case 'a':
			{
				int armor = GetClientArmor(param1);
				if (armor <= 0)
					PrintToChat(param1, "%t", "Upgrade No Longer Owned");
				else
					DropArmor(param1, armor);
			}
			case 'b':
			{
				if (!ClientHasBoots(param1))
					PrintToChat(param1, "%t", "Upgrade No Longer Owned");
				else
					DropBoots(param1);
			}
		}

		// Redraw the menu
		ShowMenu_DropUpgrade(param1);
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
		DropAll(client);
}

public void OnClientDisconnect(int client)
{
	if (IsPlayerAlive(client))
		DropAll(client);
}

public Action Command_Dimension(int client, int args)
{
	if (!validMap)
	{
		ReplyToCommand(client, "%t", "Wrong Map");
		return Plugin_Handled;
	}

	if (!client)
		return Plugin_Handled;
	
	char mapName[32];
	GetCurrentMap(mapName, sizeof(mapName));


	ShowMenu_Home(client);
	return Plugin_Handled;
}

public Action Command_Overview(int client, int args)
{
	if (!validMap)
	{
		ReplyToCommand(client, "%t", "Wrong Map");
		return Plugin_Handled;
	}

	int target = client;

	if (args > 0)
	{
		char arg[MAX_NAME_LENGTH];
		GetCmdArg(1, arg, sizeof(arg));
		
		if ((target = FindTarget(client, arg, .immunity=false)) == -1)
			return Plugin_Handled;
	}
	
	int id = GetEconomyID(target);
	if (id != INVALID_ECONOMY_ID)
	{
		PrintToServer("Points: %d", GetClientPoints(id));
		PrintToServer("Point upgrades: %d", PointCapLevel_Get(id));
	}

	PrintToServer("Health: %d", GetClientHealth(target));
	PrintToServer("Health upgrades: %d", MaxHealthLevel_Get(target));
	PrintToServer("Armor: %d", GetClientArmor(target));
	PrintToServer("Boots: %d", ClientHasBoots(target));
	return Plugin_Handled;
}

public void OnMapStart()
{
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));
	validMap = StrContains(mapName, "nmo_dimension_time") == 0;

	// Shouldn't be needed but..
	PrecacheModel(MDL_MONEYBUNDLE);
	PrecacheModel(MDL_SUITCASE);
	PrecacheModel(MDL_POLICEVEST);
	PrecacheModel(MDL_SHOE);
	PrecacheModel(MDL_HEALTHVIAL);

	for (int i; i < sizeof(SND_PICKUP); i++)
		PrecacheSound(SND_PICKUP[i]);

	if (lateloaded)
		ParseMapEntities();
}

public void Event_ResetMap(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(ParseMapEntities);
}

/*
 * Collect entities required for plugin logic (math_counters, game_text)
 */
void ParseMapEntities()
{
	char targetname[22];

	int numPointPerkMgr, numhealthDisplay, numPointCounter;

	int e = -1;
	while ((e = FindEntityByClassname(e, "math_counter")) != -1)
	{
		GetEntityTargetname(e, targetname, sizeof(targetname));

		if (StrEqual(targetname[2], "_pointcaptier"))
		{
			int index = StringToInt(targetname[1]);
			pointPerkMgr[index] = e;
			numPointPerkMgr++;
		}
		else if (StrEqual(targetname[2], "_golds"))
		{
			int index = StringToInt(targetname[1]);
			pointCounter[index] = e;
			numPointCounter++;
		}
	}

	e = -1;
	while ((e = FindEntityByClassname(e, "game_text")) != -1)
	{
		GetEntityTargetname(e, targetname, sizeof(targetname));

		if (StrContains(targetname, "text_chn2_healthtier") == 0)
		{
			int index = StringToInt(targetname[20]);
			healthDisplay[index] = e;
			numhealthDisplay++;
		}
	}

	if (numPointPerkMgr + numhealthDisplay + numPointCounter != 20)
		SetFailState("Failed to cache required entities. "
			... "Point managers: %d - Health managers: %d - Point counters: %d", 
			numPointPerkMgr, numhealthDisplay, numPointCounter);
}

public Action Command_Impulse(int client, int args)
{
	if (!validMap)
	{
		ReplyToCommand(client, "%t", "Wrong Map");
		return Plugin_Handled;
	}

	for (int i; i < MAX_MAXHEALTH_LVL; i++)
	{
		int hperk = SpawnHealthPerk();
		ClientPerformThrow(client, hperk);
	}

	int cash = SpawnCash(30);
	ClientPerformThrow(client, cash);

	int armor = SpawnArmor(100);
	ClientPerformThrow(client, armor);

	int boots = SpawnBoots();
	ClientPerformThrow(client, boots);

	for (int i; i < MAX_POINTCAP_LVL; i++)
	{
		int pperk = SpawnPointsPerk();
		ClientPerformThrow(client, pperk);
	}

	return Plugin_Handled;
}

int ClientPerformThrow(int client, int item)
{
	float position[3], angles[3], velocity[3];
	
	GetClientEyeAngles(client, velocity);
	GetAngleVectors(velocity, velocity, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(velocity, velocity);
	ScaleVector(velocity, 100.0);

	GetClientEyePosition(client, position);
	position[2] -= 10.0;

	angles[1] = GetRandomFloat(0.0, 270.0);
	angles[2] = GetRandomFloat(0.0, 270.0);

	TeleportEntity(item, position, angles, velocity);
}

/*
 * Drop cash bundle when the client holds the drop key with their fists equipped
 * If Backpack plugin is loaded use unload key instead
 */
public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	static float nextDropThink[MAXPLAYERS+1];

	if (buttons & IN_ALT2)
	{
		float curTime = GetTickedTime();
		if (curTime < nextDropThink[client])
			return;

		nextDropThink[client] = curTime + 0.3;

		char curWeapon[20];
		GetClientWeapon(client, curWeapon, sizeof(curWeapon));

		if (StrEqual(curWeapon, "me_fists"))
		{
			int id = GetEconomyID(client);
			if (id != INVALID_ECONOMY_ID && GetClientPoints(id) > 0)
				DropCash(client, id, 1);
		}
	}
}

void DropGeneric(int client, int item)
{
	if (item != -1)
	{
		ClientPerformThrow(client, item);
		InventorySound(client);
	}
}

/*
 * Plays a generic clothes sound
 */
void InventorySound(int client)
{
	int rnd = GetRandomInt(0, sizeof(SND_PICKUP) - 1);
	EmitSoundToAll(SND_PICKUP[rnd], client);
}

/*
 * Unequip speed boots from client and drop them on the ground.
 * This assumes ClientHasBoots == true was checked beforehand
 */
void DropBoots(int client)
{
	SetClientBoots(client, false);
	DropGeneric(client, SpawnBoots());
}

/*
 * Unequip armor piece from client and drop it on the ground.
 * This assumes GetClientArmor > 0 was checked beforehand
 */
void DropArmor(int client, charge)
{
	SetClientArmor(client, 0);
	DropGeneric(client, SpawnArmor(charge));
}

/*
 * Make client drop a cash bundle and decrease their points respectively. 
 * This assumes GetClientPoints > 0 was checked beforehand
 */
void DropCash(int client, int economyID, int amount)
{
	RemoveClientPoints(economyID, amount);
	DropGeneric(client, SpawnCash(amount));
}

/*
 * Drop a maxpoints perk from a client and decrease their maxpoints perk level. 
 * This assumes PointCapLevel_Get > 0 was checked beforehand
 */
void DropPointsPerk(int client, int economyID)
{
	PointCapLevel_Decrease(economyID);
	DropGeneric(client, SpawnPointsPerk());
}

/*
 * Drop a maxhealth perk from a client and decrease their maxhealth perk level. 
 * This assumes MaxHealthLevel_Get > 0 was checked beforehand
 */
void DropHealthPerk(int client)
{
	MaxHealthLevel_Decrease(client);
	ClientPerformThrow(client, SpawnHealthPerk());
}

/*
 * Triggered when a cash bundle is picked up (not including vanilla)
 */
public Action OnPickup_Cash(int cash, int activator, int caller, UseType type, float value)
{
	if (!IsValidClient(caller) || !IsValidEntity(cash))
		return Plugin_Handled;

	int id = GetEconomyID(caller);
	if (id == INVALID_ECONOMY_ID)
		return Plugin_Handled; // Don't allow pick up, makes it easier to spam use

	entData[cash] = IncreaseClientPoints(id, entData[cash]);

	if (entData[cash] <= 0)
		RemoveEntity(cash);

	InventorySound(caller);
	return Plugin_Handled;
}

/*
 * Triggered when an armor piece is picked up (not including vanilla)
 */
public Action OnPickup_Armor(int armor, int activator, int caller, UseType type, float value)
{
	if (!IsValidClient(caller) || !IsValidEntity(armor))
		return Plugin_Handled;

	if (!SetClientArmor(caller, entData[armor]))
		return Plugin_Continue;

	RemoveEntity(armor);
	InventorySound(caller);
	return Plugin_Handled;
}

/*
 * Triggered when boots are picked up (not including vanilla)
 */
public Action OnPickup_Boots(int boots, int activator, int caller, UseType type, float value)
{
	if (!IsValidClient(caller) || !IsValidEntity(boots))
		return Plugin_Handled;

	if (!SetClientBoots(caller, true))
		return Plugin_Continue;

	RemoveEntity(boots);
	InventorySound(caller);
	return Plugin_Handled;
}

/*
 * Triggered when a maxhealth perk is picked up (not including vanilla)
 */
public Action OnPickup_HealthPerk(int perk, int activator, int caller, UseType type, float value)
{
	if (!IsValidClient(caller) || !IsValidEntity(perk))
		return Plugin_Handled;

	if (!MaxHealthLevel_Increase(caller))
		return Plugin_Continue;

	RemoveEntity(perk);
	InventorySound(caller);
	return Plugin_Handled;
}

/*
 * Triggered when a maxpoints perk is picked up (not including vanilla)
 */
public Action OnPickup_PointsPerk(int perk, int activator, int caller, UseType type, float value)
{
	if (!IsValidClient(caller) || !IsValidEntity(perk))
		return Plugin_Handled;

	int id = GetEconomyID(caller);
	if (id == INVALID_ECONOMY_ID)
		return Plugin_Handled;

	if (!PointCapLevel_Increase(id))
		return Plugin_Continue; // Allow us to move it out of the way

	RemoveEntity(perk);
	InventorySound(caller);
	return Plugin_Handled;
}

/**
 * Spawns perk to increase maxhealth that can be picked up by other players
 *
 * @return            Entity index or -1 if it failed to spawn
 */
int SpawnHealthPerk()
{
	int perk = CreateEntityByName("prop_physics_override");
	if (perk != -1)
	{
		DispatchKeyValue(perk, "spawnflags", "260");
		DispatchKeyValue(perk, "model", MDL_HEALTHVIAL);
		if (DispatchSpawn(perk))
		{
			BlinkEntity(perk);
			SDKHook(perk, SDKHook_Use, OnPickup_HealthPerk);
			ScheduleDespawn(perk);
		}
	}
	return perk;
}

/**
 * Spawns perk to increase maxpoints that can be picked up by other players
 *
 * @return            Entity index or -1 if it failed to spawn
 */
int SpawnPointsPerk()
{
	int perk = CreateEntityByName("prop_physics_override");
	if (perk != -1)
	{
		DispatchKeyValue(perk, "spawnflags", "260");
		DispatchKeyValue(perk, "modelscale", "0.8");
		DispatchKeyValue(perk, "model", MDL_SUITCASE);
		if (DispatchSpawn(perk))
		{
			BlinkEntity(perk);
			SDKHook(perk, SDKHook_Use, OnPickup_PointsPerk);
			ScheduleDespawn(perk);
		}

	}
	return perk;
}

/**
 * Spawns speed boots that can be picked up by other players
 *
 * @return            Entity index or -1 if it failed to spawn
 */
int SpawnBoots()
{
	int boots = CreateEntityByName("prop_physics_override");
	if (boots != -1)
	{
		DispatchKeyValue(boots, "spawnflags", "260");
		DispatchKeyValue(boots, "model", MDL_SHOE);
		if (DispatchSpawn(boots))
		{
			BlinkEntity(boots);
			SDKHook(boots, SDKHook_Use, OnPickup_Boots);
			ScheduleDespawn(boots);
		}
	}
	return boots;
}

/**
 * Spawns an armor that can be picked up by other players
 *
 * @param charge      Charge provided by the armor
 * @return            Entity index or -1 if it failed to spawn
 */
int SpawnArmor(int charge)
{
	int armor = CreateEntityByName("prop_physics_override");
	if (armor != -1)
	{
		entData[armor] = charge;
		DispatchKeyValue(armor, "spawnflags", "260");
		DispatchKeyValue(armor, "model", MDL_POLICEVEST);
		if (DispatchSpawn(armor))
		{
			BlinkEntity(armor);
			SDKHook(armor, SDKHook_Use, OnPickup_Armor);
			ScheduleDespawn(armor);
		}
	}
	return armor;
}

/**
 * Spawns a cash bundle that can be picked up by other players
 *
 * @param amount      Number of points the bundle gives
 * @return            Entity index or -1 if it failed to spawn
 */
int SpawnCash(int amount)
{
	int cash = CreateEntityByName("prop_physics_override");

	if (cash != -1)
	{
		entData[cash] = amount;
		DispatchKeyValue(cash, "spawnflags", "260");
		DispatchKeyValue(cash, "model", MDL_MONEYBUNDLE);

		if (DispatchSpawn(cash))
		{
			BlinkEntity(cash);
			SDKHook(cash, SDKHook_Use, OnPickup_Cash);
			ScheduleDespawn(cash);
		}
	}
	return cash;
}

/**
 * Makes entity despawn after a period of time (set by ConVar)
 *
 * @param item      	Entity index
 * @return            Entity index or -1 if it failed to spawn
 */
void ScheduleDespawn(int item)
{
	static char str[35];
	FormatEx(str, sizeof(str), "OnUser1 !self:Kill::%d:-1", cvItemDespawn.IntValue);
	SetVariantString(str);
	AcceptEntityInput(item, "AddOutput");
	AcceptEntityInput(item, "FireUser1");
}

void BlinkEntity(int entity)
{
	int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
	SetEntProp(entity, Prop_Send, "m_fEffects", effects|EF_ITEM_BLINK);
}

bool ClientHasBoots(int client)
{
	return GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue") == 1.3;
}

bool SetClientBoots(int client, bool toggle)
{
	if (toggle)
	{
		if (ClientHasBoots(client))
			return false;

		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.3);
	}
	else
	{
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
	}

	return true;
}

int GetClientPoints(int id)
{
	static int offset = -1;
	if (offset == -1)
		offset = FindDataMapInfo(pointCounter[id], "m_OutValue");

	return RoundToFloor(GetEntDataFloat(pointCounter[id], offset));
}

void RemoveClientPoints(int id, int amount)
{
	SetVariantInt(amount);
	AcceptEntityInput(pointCounter[id], "Subtract");
}

/**
 * Increases a client's points, respecting the maximum bound
 *
 * @param amount      Number of points to add
 * @return            Excess points that didn't fit
 */
int IncreaseClientPoints(int id, int amount)
{
	int canTake = GetClientMaxPoints(id) - GetClientPoints(id);
	if (canTake <= 0)
		return amount;

	if (canTake > amount)
		canTake = amount;

	SetVariantInt(canTake);
	AcceptEntityInput(pointCounter[id], "Add");
	return amount - canTake;
}

/**
 * Gives client armor if they don't have any
 *
 * @param charge      Armor charge
 * @return            false if client had armor already
 */
bool SetClientArmor(int client, int charge)
{
	if (charge > 0 && GetClientArmor(client) > 0)
		return false;

	SetEntProp(client, Prop_Send, "m_ArmorValue", charge);
	return true;
}

bool IsValidClient(int client)
{
	return 0 < client <= MaxClients && IsClientInGame(client);
}

int GetEntityTargetname(int entity, char[] buffer, int maxlen)
{
	return GetEntPropString(entity, Prop_Data, "m_iName", buffer, maxlen);
}

bool PointCapLevel_Increase(int id)
{
	// Never hit 4, else client gets a refund of 15 points
	if (PointCapLevel_Get(id) < MAX_POINTCAP_LVL)
	{
		SetVariantInt(1);
		AcceptEntityInput(pointPerkMgr[id], "Add");
		return true;
	}
	
	return false;
}

void PointCapLevel_Decrease(int id)
{
	SetVariantInt(1);
	AcceptEntityInput(pointPerkMgr[id], "Subtract");
}

int PointCapLevel_Get(int id)
{
	static int offset = -1;
	if (offset == -1)
		offset = FindDataMapInfo(pointPerkMgr[id], "m_OutValue");

	return RoundToFloor(GetEntDataFloat(pointPerkMgr[id], offset));
}

bool MaxHealthLevel_Increase(int client)
{
	int curLvl = MaxHealthLevel_Get(client);

	if (curLvl >= MAX_MAXHEALTH_LVL)
		return false;

	curLvl++;
	SetEntProp(client, Prop_Data, "m_iMaxHealth", 100 + 30 * curLvl);

	SetVariantString("!activator");
	AcceptEntityInput(healthDisplay[curLvl], "Display", client);
	return true;
}

int GetClientMaxPoints(int id)
{
	return RoundToFloor(GetEntPropFloat(pointCounter[id], Prop_Data, "m_flMax"));
}

void MaxHealthLevel_Decrease(int client)
{
	int curLvl = MaxHealthLevel_Get(client);

	if (curLvl <= 0)
		return;

	curLvl--;
	int newMaxHealth = 100 + 30 * curLvl;
	SetEntProp(client, Prop_Data, "m_iMaxHealth", newMaxHealth);

	SetVariantString("!activator");
	AcceptEntityInput(healthDisplay[curLvl], "Display", client);

	// Clamp health if it became higher than the new max
	if (GetClientHealth(client) > newMaxHealth)
		SetEntityHealth(client, newMaxHealth);
}

int MaxHealthLevel_Get(int client)
{
	int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	int lvl = (maxHealth - 100) / 30; 
	return (lvl < 0) ? 0 : lvl;
}

int GetEconomyID(int client)
{
	int id = -1;
	static char name[8];
	if (GetEntityTargetname(client, name, sizeof(name)) && 
		(StringToIntEx(name[6], id) && 0 <= id < MAX_ECO_PLAYERS))
			return id;

	return INVALID_ECONOMY_ID;
}
