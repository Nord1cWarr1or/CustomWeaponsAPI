#include <amxmodx>
#include <reapi>
#include <hamsandwich>
#include <json>
#include <regex>
#include <cwapi>

#pragma semicolon 1

#define DEBUG // Закомментировать чтобы запретить бесплатную выдачу пушек
//#define SUPPORT_RESTRICT // Поддержка запрещалки пушек

#define WEAPON_PISTOLS_BITSUMM (BIT(_:WEAPON_P228)|BIT(_:WEAPON_GLOCK)|BIT(_:WEAPON_ELITE)|BIT(_:WEAPON_FIVESEVEN)|BIT(_:WEAPON_USP)|BIT(_:WEAPON_GLOCK18)|BIT(_:WEAPON_DEAGLE))
#define WEAPONS_IMPULSE_OFFSET 4354
#define GetWeapFullName(%0) fmt("weapon_%s",%0)
#define CUSTOM_WEAPONS_COUNT ArraySize(CustomWeapons)
#define GetWeapId(%0) get_entvar(%0,var_impulse)-WEAPONS_IMPULSE_OFFSET
#define IsCustomWeapon(%0) (0 <= %0 < CUSTOM_WEAPONS_COUNT)
#define IsGrenade(%0) (equal(%0, "hegrenade") || equal(%0, "smokegrenade") || equal(%0, "flashbang"))
#define IsWeaponSilenced(%0) bool:((WPNSTATE_M4A1_SILENCED|WPNSTATE_USP_SILENCED)&get_member(%0,m_Weapon_iWeaponState))
#define IsPistol(%0) (WEAPON_PISTOLS_BITSUMM&BIT(rg_get_iteminfo(%0,ItemInfo_iId)))

#if defined SUPPORT_RESTRICT
    forward WeaponsRestrict_LoadingWeapons_Post();
    native WeaponsRestrict_AddWeapon(const WeaponId, const WeaponName[32]);
#endif

enum {
    CWAPI_ERR_UNDEFINED_EVENT = 0,
    CWAPI_ERR_WEAPON_NOT_FOUND,
    CWAPI_ERR_CANT_EXECUTE_FWD,
    CWAPI_ERR_DUPLICATE_WEAPON_NAME,
}

enum E_Fwds{
    F_LoadWeaponsPost,
};

new Trie:WeaponsNames;
new Array:CustomWeapons;

new Fwds[E_Fwds];

new const PLUG_NAME[] = "Custom Weapons API";
new const PLUG_VER[] = "0.4.0-beta";

public plugin_init(){
    register_dictionary("cwapi.txt");
    
    RegisterHookChain(RG_CWeaponBox_SetModel, "Hook_WeaponBoxSetModel", false);
    RegisterHookChain(RG_CWeaponBox_SetModel, "Hook_WeaponBoxSetModel_Post", true);
    RegisterHookChain(RG_CBasePlayer_AddPlayerItem, "Hook_PlayerAddItem", true);
    RegisterHookChain(RG_CBasePlayer_TakeDamage, "Hook_PlayerTakeDamage", false);

    // Покупка пушки (Только если указана цена)
    register_clcmd("CWAPI_Buy", "Cmd_Buy");
    #if defined DEBUG
        // Бесплатная выдача пушки (Для тестов)
        register_clcmd("CWAPI_Give", "Cmd_GiveCustomWeapon");
    #endif

    server_print("[%s v%s] loaded.", PLUG_NAME, PLUG_VER);
}

public plugin_precache(){
    register_plugin(PLUG_NAME, PLUG_VER, "ArKaNeMaN");
    
    InitForwards();
    LoadWeapons();
    if(CUSTOM_WEAPONS_COUNT < 1)
        set_fail_state("[WARNING] No loaded weapons");

    server_print("[%s v%s] %d custom weapons loaded.", PLUG_NAME, PLUG_VER, CUSTOM_WEAPONS_COUNT);
}

public plugin_natives(){
    register_native("CWAPI_RegisterHook", "Native_RegisterHook");
    register_native("CWAPI_GiveWeapon", "Native_GiveWeapon");
    register_native("CWAPI_GetWeaponsList", "Native_GetWeaponsList");
    register_native("CWAPI_GetWeaponData", "Native_GetWeaponData");
    register_native("CWAPI_AddCustomWeapon", "Native_AddCustomWeapon");
}

public Native_GiveWeapon(){
    enum {Arg_UserId = 1, Arg_WeaponName};
    static UserId; UserId = get_param(Arg_UserId);
    static WeaponName[32]; get_string(Arg_WeaponName, WeaponName, charsmax(WeaponName));

    if(!TrieKeyExists(WeaponsNames, WeaponName)){
        log_error(CWAPI_ERR_WEAPON_NOT_FOUND, "Weapon '%s' not found", WeaponName);
        return -1;
    }
    static WeaponId; TrieGetCell(WeaponsNames, WeaponName, WeaponId);
    return GiveCustomWeapon(UserId, WeaponId);
}

public Native_RegisterHook(const PluginId, const Params){
    enum {Arg_WeaponName = 1, Arg_Event, Arg_FuncName};
    new WeaponName[32]; get_string(Arg_WeaponName, WeaponName, charsmax(WeaponName));
    new CWAPI_WeaponEvents:Event = CWAPI_WeaponEvents:get_param(Arg_Event);
    new FuncName[64]; get_string(Arg_FuncName, FuncName, charsmax(FuncName));

    if(!TrieKeyExists(WeaponsNames, WeaponName))
        return -1;

    new WeaponId; TrieGetCell(WeaponsNames, WeaponName, WeaponId);
    new Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, WeaponId, Data);

    if(Data[CWAPI_WD_CustomHandlers][Event] == Invalid_Array){
        Data[CWAPI_WD_CustomHandlers][Event] = ArrayCreate();
        ArraySetArray(CustomWeapons, WeaponId, Data);
    }
    
    new FwdId = _CreateOneForward(PluginId, FuncName, Event);
    new HandlerId = ArrayPushCell(Data[CWAPI_WD_CustomHandlers][Event], _:FwdId);

    return HandlerId;
}

public Array:Native_GetWeaponsList(){
    return ArrayClone(CustomWeapons);
}

public Native_GetWeaponData(){
    enum {Arg_WeaponId = 1, Arg_WeaponData};
    static WeaponData[CWAPI_WeaponData];
    ArrayGetArray(CustomWeapons, get_param(Arg_WeaponId), WeaponData);
    return set_array(Arg_WeaponData, WeaponData, CWAPI_WeaponData);
}

public Native_AddCustomWeapon(){
    enum {Arg_WeaponData = 1}
    new Data[CWAPI_WeaponData]; get_array(Arg_WeaponData, Data, CWAPI_WeaponData);

    if(TrieKeyExists(WeaponsNames, Data[CWAPI_WD_Name])){
        log_error(CWAPI_ERR_DUPLICATE_WEAPON_NAME, "Weapon '%s' already exists.", Data[CWAPI_WD_Name]);
        return -1;
    }

    if(Data[CWAPI_WD_CustomHandlers] != Invalid_Array)
        for(new i = 1; i < _:CWAPI_WeaponEvents; i++)
            ArrayDestroy(Data[CWAPI_WD_CustomHandlers][CWAPI_WeaponEvents:i]);

    new WeaponId = ArrayPushArray(CustomWeapons, Data);
    TrieSetCell(WeaponsNames, Data[CWAPI_WD_Name], WeaponId);
    return WeaponId;
}

CallWeaponEvent(const WeaponId, const CWAPI_WeaponEvents:Event, const ItemId, const any:...){
    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, WeaponId, Data);
    if(Data[CWAPI_WD_CustomHandlers][Event] == Invalid_Array)
        return true;

    //log_amx("[DEBUG] CallWeaponEvent: WeaponId = %d", WeaponId);
    //log_amx("[DEBUG] CallWeaponEvent: Event = %d", _:Event);
    //log_amx("[DEBUG] CallWeaponEvent: ItemId = %d", ItemId);
    //log_amx("[DEBUG] CallWeaponEvent: numargs() = %d", numargs());
    //for(new i = 1; i <= numargs(); i++){
    //    log_amx("[DEBUG] CallWeaponEvent:     getarg(%d) = (int) %d", i, _:getarg(i));
    //    log_amx("[DEBUG] CallWeaponEvent:     getarg(%d) = (float) %.2f", i, Float:getarg(i));
    //}
    
    static FwdId, Return, Status;
    for(new i = 0; i < ArraySize(Data[CWAPI_WD_CustomHandlers][Event]); i++){
        FwdId = ArrayGetCell(Data[CWAPI_WD_CustomHandlers][Event], i);

        Return = CWAPI_RET_CONTINUE;
        switch(Event){
            case CWAPI_WE_PrimaryAttack: Status = ExecuteForward(FwdId, Return, ItemId);
            case CWAPI_WE_SecondaryAttack: Status = ExecuteForward(FwdId, Return, ItemId);
            case CWAPI_WE_Reload: Status = ExecuteForward(FwdId, Return, ItemId);
            case CWAPI_WE_Deploy: Status = ExecuteForward(FwdId, Return, ItemId);
            case CWAPI_WE_Holster: Status = ExecuteForward(FwdId, Return, ItemId);
            case CWAPI_WE_Damage: Status = ExecuteForward(FwdId, Return, ItemId, _:getarg(3), Float:getarg(4), _:getarg(5));
            case CWAPI_WE_Droped: Status = ExecuteForward(FwdId, Return, ItemId, getarg(3));
            case CWAPI_WE_AddItem: Status = ExecuteForward(FwdId, Return, ItemId, getarg(3));
            case CWAPI_WE_Take: Status = ExecuteForward(FwdId, Return, ItemId, getarg(3));
            default: {
                log_error(CWAPI_ERR_UNDEFINED_EVENT, "Undefined weapon event '%d'.", _:Event);
                Status = 0;
            }
        }

        if(!Status)
            log_error(CWAPI_ERR_CANT_EXECUTE_FWD, "Can't execute event forward.");

        if(Return == CWAPI_RET_HANDLED)
            break;
    }

    if(Return == CWAPI_RET_HANDLED)
        return false;

    return true;
}

_CreateOneForward(const PluginId, const FuncName[], const CWAPI_WeaponEvents:Event){
    switch(Event){
        case CWAPI_WE_PrimaryAttack: return CreateOneForward(PluginId, FuncName, FP_CELL);
        case CWAPI_WE_SecondaryAttack: return CreateOneForward(PluginId, FuncName, FP_CELL);
        case CWAPI_WE_Reload: return CreateOneForward(PluginId, FuncName, FP_CELL);
        case CWAPI_WE_Deploy: return CreateOneForward(PluginId, FuncName, FP_CELL);
        case CWAPI_WE_Holster: return CreateOneForward(PluginId, FuncName, FP_CELL);
        case CWAPI_WE_Damage: return CreateOneForward(PluginId, FuncName, FP_CELL, FP_CELL, FP_FLOAT, FP_CELL);
        case CWAPI_WE_Droped: return CreateOneForward(PluginId, FuncName, FP_CELL, FP_CELL);
        case CWAPI_WE_AddItem: return CreateOneForward(PluginId, FuncName, FP_CELL, FP_CELL);
        case CWAPI_WE_Take: return CreateOneForward(PluginId, FuncName, FP_CELL, FP_CELL);
    }
    return log_error(CWAPI_ERR_UNDEFINED_EVENT, "Undefined weapon event '%d'", _:Event);
}

#if defined DEBUG
    public Cmd_GiveCustomWeapon(const Id){
        static WeaponName[32]; read_argv(1, WeaponName, charsmax(WeaponName));
        if(TrieKeyExists(WeaponsNames, WeaponName)){
            static WeaponId; TrieGetCell(WeaponsNames, WeaponName, WeaponId);
            if(GiveCustomWeapon(Id, WeaponId) != -1) client_print_color(Id, print_team_default, "%L", LANG_PLAYER, "WEAPON_GIVE_SUCCESS", WeaponName);
            else client_print_color(Id, print_team_default, "%L", LANG_PLAYER, "WEAPON_GIVE_ERROR");
            return PLUGIN_HANDLED;
        }
        client_print_color(Id, print_team_default, "%L", LANG_PLAYER, "WEAPON_NOT_FOUND", WeaponName);
        return PLUGIN_CONTINUE;
    }
#endif

public Cmd_Buy(const Id){
    if(!is_user_alive(Id)){
        client_print(Id, print_center, "%L", LANG_PLAYER, "YOU_DEAD");
        return PLUGIN_HANDLED;
    }

    if(!IsUserInBuyZone(Id)){
        client_print(Id, print_center, "%L", LANG_PLAYER, "OUT_OF_BUYZONE");
        return PLUGIN_HANDLED;
    }

    static WeaponName[32]; read_argv(1, WeaponName, charsmax(WeaponName));

    if(!TrieKeyExists(WeaponsNames, WeaponName)){
        client_print_color(Id, print_team_default, "%L", LANG_PLAYER, "WEAPON_NOT_FOUND", WeaponName);
        return PLUGIN_CONTINUE;
    }

    static WeaponId; TrieGetCell(WeaponsNames, WeaponName, WeaponId);
    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, WeaponId, Data);
    if(!Data[CWAPI_WD_Price]){
        client_print_color(Id, print_team_default, "%L", LANG_PLAYER, "WEAPON_BUY_NO_PRICE", WeaponName);
        return PLUGIN_HANDLED;
    }
    if(get_member(Id, m_iAccount) < Data[CWAPI_WD_Price]){
        client_print_color(Id, print_team_default, "%L", LANG_PLAYER, "WEAPON_BUY_NO_MONEY", WeaponName);
        return PLUGIN_HANDLED;
    }
    if(GiveCustomWeapon(Id, WeaponId) != -1){
        rg_add_account(Id, -Data[CWAPI_WD_Price], AS_ADD);
        client_print_color(Id, print_team_default, "%L", LANG_PLAYER, "WEAPON_BUY_SUCCESS", WeaponName, Data[CWAPI_WD_Price]);
    }
    else client_print_color(Id, print_team_default, "%L", LANG_PLAYER, "WEAPON_BUY_ERROR");
    return PLUGIN_HANDLED;
}

public Hook_WeaponBoxSetModel(const WeaponBox){
    static ItemId;
    if(!(ItemId = GetItemFromWeaponBox(WeaponBox)))
        return;

    static WeaponId; WeaponId = GetWeapId(ItemId);
    if(!IsCustomWeapon(WeaponId))
        return;

    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, WeaponId, Data);

    if(Data[CWAPI_WD_Models][CWAPI_WM_W][0])
        SetHookChainArg(2, ATYPE_STRING, Data[CWAPI_WD_Models][CWAPI_WM_W], PLATFORM_MAX_PATH-1);

    return;
}

public Hook_WeaponBoxSetModel_Post(const WeaponBox){
    static ItemId;
    if(!(ItemId = GetItemFromWeaponBox(WeaponBox)))
        return;

    static WeaponId; WeaponId = GetWeapId(ItemId);
    if(!IsCustomWeapon(WeaponId))
        return;

    CallWeaponEvent(WeaponId, CWAPI_WE_Droped, ItemId, WeaponBox);

    return;
}

public Hook_PlayerAddItem(const UserId, const ItemId){
    static WeaponId; WeaponId = GetWeapId(ItemId);

    if(!IsCustomWeapon(WeaponId))
        return;
    
    if(!is_user_connected(UserId))
        return;

    CallWeaponEvent(GetWeapId(ItemId), CWAPI_WE_AddItem, ItemId, UserId);

    return;
}

public Hook_PlayerTakeDamage(const Victim, Inflictor, Attacker, Float:Damage, DamageBits){
    if(DamageBits & DMG_GRENADE)
        return HC_CONTINUE;

    if(!is_user_connected(Victim) || !is_user_connected(Attacker))
        return HC_CONTINUE;
        
    static ItemId; ItemId = get_member(Attacker, m_pActiveItem);

    if(is_nullent(ItemId))
        return HC_CONTINUE;

    static WeaponId; WeaponId = GetWeapId(ItemId);

    if(!IsCustomWeapon(WeaponId))
        return HC_CONTINUE;

    //log_amx("[DEBUG] Hook_PlayerTakeDamage: ItemId = %в", ItemId);
    //log_amx("[DEBUG] Hook_PlayerTakeDamage: Victim = %n", Victim);
    //log_amx("[DEBUG] Hook_PlayerTakeDamage: Damage = %.2f", Damage);
    //log_amx("[DEBUG] Hook_PlayerTakeDamage: DamageBits = %d", DamageBits);

    if(!CallWeaponEvent(WeaponId, CWAPI_WE_Damage, ItemId, Victim, Damage, DamageBits)){
        SetHookChainReturn(ATYPE_INTEGER, 0);
        return HC_SUPERCEDE;
    }

    return HC_CONTINUE;
}

public Hook_PlayerItemDeploy(const ItemId){
    if(!IsCustomWeapon(GetWeapId(ItemId)))
        return;
    
    static Id; Id = get_member(ItemId, m_pPlayer);

    if(!is_user_connected(Id))
        return;
    
    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, GetWeapId(ItemId), Data);

    if(Data[CWAPI_WD_Models][CWAPI_WM_V][0])
        set_entvar(Id, var_viewmodel, Data[CWAPI_WD_Models][CWAPI_WM_V][0]);
    
    if(Data[CWAPI_WD_Models][CWAPI_WM_P][0])
        set_entvar(Id, var_weaponmodel, Data[CWAPI_WD_Models][CWAPI_WM_P][0]);
    
    if(Data[CWAPI_WD_DeployTime] > 0.0)
        SetWeaponNextAttack(ItemId, Data[CWAPI_WD_DeployTime]);

    if(Data[CWAPI_WD_Accuracy] > 0.0)
        set_member(ItemId, m_Weapon_flAccuracy, Data[CWAPI_WD_Accuracy]);

    CallWeaponEvent(GetWeapId(ItemId), CWAPI_WE_Deploy, ItemId);

    return;
}

public Hook_PlayerItemHolster(const ItemId){
    if(!IsCustomWeapon(GetWeapId(ItemId)))
        return;

    CallWeaponEvent(GetWeapId(ItemId), CWAPI_WE_Holster, ItemId);

    return;
}

public Hook_PlayerItemReloaded(const ItemId){
    static Id; Id = get_member(ItemId, m_pPlayer);
    if(!is_user_connected(Id) || !IsCustomWeapon(GetWeapId(ItemId)))
        return HAM_IGNORED;

    if(
        get_member(ItemId, m_Weapon_iClip) < rg_get_iteminfo(ItemId, ItemInfo_iMaxClip) &&
        CallWeaponEvent(GetWeapId(ItemId), CWAPI_WE_Reload, ItemId)
    )
        return HAM_IGNORED;

    SetWeaponIdleAnim(Id, ItemId);

    return HAM_SUPERCEDE;
}

public Hook_PlayerItemReloaded_Post(const ItemId){
    if(!IsCustomWeapon(GetWeapId(ItemId)))
        return HAM_IGNORED;

    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, GetWeapId(ItemId), Data);
    
    if(Data[CWAPI_WD_ReloadTime])
        if(get_member(ItemId, m_Weapon_fInSpecialReload)) set_member(ItemId, m_Weapon_flNextReload, Data[CWAPI_WD_ReloadTime]);
        else SetWeaponNextAttack(ItemId, Data[CWAPI_WD_ReloadTime]);

    return HAM_IGNORED;
}

public Hook_PlayerGetMaxSpeed(const ItemId){
    if(!IsCustomWeapon(GetWeapId(ItemId)))
        return HAM_IGNORED;
    
    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, GetWeapId(ItemId), Data);

    if(Data[CWAPI_WD_MaxWalkSpeed]){
        SetHamReturnFloat(Data[CWAPI_WD_MaxWalkSpeed]);
        return HAM_SUPERCEDE;
    }

    return HAM_IGNORED;
}

public Hook_PrimaryAttack_Pre(ItemId){
    if(!IsCustomWeapon(GetWeapId(ItemId)))
        return;

    if(get_member(ItemId, m_Weapon_iClip) < 1)
        return;

    if(IsPistol(ItemId) && get_member(ItemId, m_Weapon_iShotsFired)+1 > 1)
        return;
    
    CallWeaponEvent(GetWeapId(ItemId), CWAPI_WE_PrimaryAttack, ItemId);
    
    return;
}

public Hook_PrimaryAttack(ItemId){
    static WeaponId; WeaponId = GetWeapId(ItemId);
    if(!IsCustomWeapon(WeaponId))
        return HAM_IGNORED;

    if(get_member(ItemId, m_Weapon_fFireOnEmpty))
        return HAM_IGNORED;

    if(IsPistol(ItemId) && get_member(ItemId, m_Weapon_iShotsFired) > 1)
        return HAM_IGNORED;

    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, WeaponId, Data);

    CallWeaponEvent(WeaponId, CWAPI_WE_PrimaryAttack, ItemId);

    if(Data[CWAPI_WD_PrimaryAttackRate] > 0.0)
        SetWeaponNextAttack(ItemId, Data[CWAPI_WD_PrimaryAttackRate]);

    static UserId; UserId = get_member(ItemId, m_pPlayer);
    if(IsWeaponSilenced(ItemId)) if(Data[CWAPI_WD_Sounds][CWAPI_WS_ShotSilent][0]) rh_emit_sound2(UserId, 0, CHAN_WEAPON, Data[CWAPI_WD_Sounds][CWAPI_WS_ShotSilent]);
    else if(Data[CWAPI_WD_Sounds][CWAPI_WS_Shot][0]) rh_emit_sound2(UserId, 0, CHAN_WEAPON, Data[CWAPI_WD_Sounds][CWAPI_WS_Shot]);

    return HAM_IGNORED;
}

public Hook_SecondaryAttack(ItemId){
    static WeaponId; WeaponId = GetWeapId(ItemId);
    if(!IsCustomWeapon(WeaponId))
        return HAM_IGNORED;

    if(!CallWeaponEvent(WeaponId, CWAPI_WE_SecondaryAttack, ItemId))
        return HAM_IGNORED;

    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, WeaponId, Data);

    if(Data[CWAPI_WD_SecondaryAttackRate] > 0.0)
        SetWeaponNextAttack(ItemId, Data[CWAPI_WD_SecondaryAttackRate]);
    
    return HAM_IGNORED;
}

// Выдача пушки
GiveCustomWeapon(const Id, const WeaponId){
    if(!is_user_alive(Id))
        return -1;

    if(!IsCustomWeapon(WeaponId))
        return -1;

    if(!CallWeaponEvent(WeaponId, CWAPI_WE_Take, WeaponId, Id))
        return -1;

    static Data[CWAPI_WeaponData]; ArrayGetArray(CustomWeapons, WeaponId, Data);

    static GiveType:WeaponGiveType;
    if(equal(Data[CWAPI_WD_DefaultName], "knife")) WeaponGiveType = GT_REPLACE;
    else if(IsGrenade(Data[CWAPI_WD_DefaultName])) WeaponGiveType = GT_APPEND;
    else WeaponGiveType = GT_DROP_AND_REPLACE;

    static ItemId; ItemId = rg_give_custom_item(
        Id,
        GetWeapFullName(Data[CWAPI_WD_DefaultName]),
        WeaponGiveType,
        WeaponId+WEAPONS_IMPULSE_OFFSET
    );

    if(is_nullent(ItemId)) return -1;

    static WeaponIdType:DefaultWeaponId; DefaultWeaponId = WeaponIdType:rg_get_iteminfo(ItemId, ItemInfo_iId);

    if(Data[CWAPI_WD_HasSecondaryAttack]) set_member(ItemId, m_Weapon_bHasSecondaryAttack, Data[CWAPI_WD_HasSecondaryAttack]);
    if(Data[CWAPI_WD_Weight]) rg_set_iteminfo(ItemId, ItemInfo_iWeight, Data[CWAPI_WD_Weight]);
    
    if(DefaultWeaponId != WEAPON_KNIFE){
        if(Data[CWAPI_WD_ClipSize]){
            rg_set_iteminfo(ItemId, ItemInfo_iMaxClip, Data[CWAPI_WD_ClipSize]);
            rg_set_user_ammo(Id, DefaultWeaponId, Data[CWAPI_WD_ClipSize]);
        }

        if(Data[CWAPI_WD_MaxAmmo]){
            rg_set_iteminfo(ItemId, ItemInfo_iMaxAmmo1, Data[CWAPI_WD_MaxAmmo]);
            rg_set_user_bpammo(Id, DefaultWeaponId, Data[CWAPI_WD_MaxAmmo]);
        }
    }

    if(Data[CWAPI_WD_Damage])
        set_member(
            ItemId, m_Weapon_flBaseDamage,
            Data[CWAPI_WD_Damage]
        );
    else if(Data[CWAPI_WD_Damage] < 0)
        set_member(
            ItemId, m_Weapon_flBaseDamage,
            0.0
        );

    if(Data[CWAPI_WD_DamageMult]){
        set_member(
            ItemId, m_Weapon_flBaseDamage,
            Float:get_member(ItemId, m_Weapon_flBaseDamage)*Data[CWAPI_WD_DamageMult]
        );

        if(DefaultWeaponId == WEAPON_M4A1)
            set_member(
                ItemId, m_M4A1_flBaseDamageSil,
                Float:get_member(ItemId, m_M4A1_flBaseDamageSil)*Data[CWAPI_WD_DamageMult]
            );
        else if(DefaultWeaponId == WEAPON_USP)
            set_member(
                ItemId, m_USP_flBaseDamageSil,
                Float:get_member(ItemId, m_USP_flBaseDamageSil)*Data[CWAPI_WD_DamageMult]
            );
        else if(DefaultWeaponId == WEAPON_FAMAS)
            set_member(
                ItemId, m_Famas_flBaseDamageBurst,
                Float:get_member(ItemId, m_Famas_flBaseDamageBurst)*Data[CWAPI_WD_DamageMult]
            );
    }

    return ItemId;
}

// Получение ID итема из WeaponBox'а
GetItemFromWeaponBox(const WeaponBox){
    for(new i = 0, ItemId; i < MAX_ITEM_TYPES; i++){
        ItemId = get_member(WeaponBox, m_WeaponBox_rgpPlayerItems, i);
        if(!is_nullent(ItemId))
            return ItemId;
    }
    return NULLENT;
}

// В зоне закупки ли игрок
bool:IsUserInBuyZone(const Id){
    static Signal[UnifiedSignals]; get_member(Id, m_signals, Signal);
    return (Signal[US_Signal] == _:SIGNAL_BUY);
}

// Установка времени до следующего выстрела
SetWeaponNextAttack(ItemId, Float:Rate){
    set_member(ItemId, m_Weapon_flNextPrimaryAttack, Rate);
    set_member(ItemId, m_Weapon_flNextSecondaryAttack, Rate);
}

SetWeaponIdleAnim(const UserId, const ItemId){
    static Anim; Anim = 0;
    if(!IsWeaponSilenced(ItemId)){
        static WeaponIdType:WeaponId; WeaponId = WeaponIdType:rg_get_iteminfo(ItemId, ItemInfo_iId);
        if(WeaponId == WEAPON_M4A1) Anim = 7;
        else if(WeaponId == WEAPON_USP) Anim = 8;
    }

    set_entvar(UserId, var_weaponanim, Anim);

    message_begin(MSG_ONE_UNRELIABLE, SVC_WEAPONANIM, .player = UserId);
    write_byte(Anim);
    write_byte(get_entvar(UserId, var_body));
    message_end();
}

// Загрузка пушек из кфг
LoadWeapons(){
    CustomWeapons = ArrayCreate(CWAPI_WeaponData);
    WeaponsNames = TrieCreate();
    new Path[PLATFORM_MAX_PATH];
    get_localinfo("amxx_configsdir", Path, charsmax(Path));
    add(Path, charsmax(Path), "/plugins/CustomWeaponsAPI/Weapons/");
    if(!dir_exists(Path)){
        set_fail_state("[ERROR] Weapons folder '%s' not found.", Path);
        return;
    }
    
    new File[PLATFORM_MAX_PATH], DirHandler, FileType:Type;
    DirHandler = open_dir(Path, File, charsmax(File), Type);
    if(!DirHandler){
        set_fail_state("[ERROR] Can't open weapons folder '%s'.", Path);
        return;
    }

    new Regex:RegEx_FileName, ret; RegEx_FileName = regex_compile("([a-z0-9]+).json$", ret, "", 0, "i");
    new JSON:Item;
    new Trie:DefWeaponsNamesList = TrieCreate();
    do{
        //log_amx("[DEBUG] New_LoadWeapons: Cycle: Item = %d ==========", CUSTOM_WEAPONS_COUNT);
        //log_amx("[DEBUG] New_LoadWeapons: Cycle: File = %s", File);
        //log_amx("[DEBUG] New_LoadWeapons: Cycle: FileType = %d", _:Type);

        if(Type != FileType_File)
            continue;
        
        if(regex_match_c(File, RegEx_FileName) <= 0)
            continue;

        new Data[CWAPI_WeaponData];

        regex_substr(RegEx_FileName, 1, Data[CWAPI_WD_Name], charsmax(Data[CWAPI_WD_Name]));
        
        //log_amx("[DEBUG] New_LoadWeapons: Cycle: Name = %s", Data[CWAPI_WD_Name]);

        format(File, charsmax(File), "%s%s", Path, File);
        Item = json_parse(File, true, true);

        //log_amx("[DEBUG] New_LoadWeapons: Cycle: Jsno Type = %d", _:json_get_type(Item));

        if(!json_is_object(Item)){
            json_free(Item);
            log_amx("[WARNING] Invalid config structure. File '%s'.", File);
            continue;
        }

        json_object_get_string(Item, "DefaultName", Data[CWAPI_WD_DefaultName], charsmax(Data[CWAPI_WD_DefaultName]));

        if(json_object_has_value(Item, "Models", JSONObject)){
            new JSON:Models = json_object_get_value(Item, "Models");

            json_object_get_string(Models, "v", Data[CWAPI_WD_Models][CWAPI_WM_V], PLATFORM_MAX_PATH-1);
            if(file_exists(Data[CWAPI_WD_Models][CWAPI_WM_V])) precache_model(Data[CWAPI_WD_Models][CWAPI_WM_V]);
            else formatex(Data[CWAPI_WD_Models][CWAPI_WM_V], PLATFORM_MAX_PATH-1, "");

            json_object_get_string(Models, "p", Data[CWAPI_WD_Models][CWAPI_WM_P], PLATFORM_MAX_PATH-1);
            if(file_exists(Data[CWAPI_WD_Models][CWAPI_WM_P])) precache_model(Data[CWAPI_WD_Models][CWAPI_WM_P]);
            else formatex(Data[CWAPI_WD_Models][CWAPI_WM_P], PLATFORM_MAX_PATH-1, "");

            json_object_get_string(Models, "w", Data[CWAPI_WD_Models][CWAPI_WM_W], PLATFORM_MAX_PATH-1);
            if(file_exists(Data[CWAPI_WD_Models][CWAPI_WM_W])) precache_model(Data[CWAPI_WD_Models][CWAPI_WM_W]);
            else formatex(Data[CWAPI_WD_Models][CWAPI_WM_W], PLATFORM_MAX_PATH-1, "");
            
            json_free(Models);
        }

        if(json_object_has_value(Item, "Sounds", JSONObject)){
            new JSON:Sounds = json_object_get_value(Item, "Sounds");

            json_object_get_string(Sounds, "ShotSilent", Data[CWAPI_WD_Sounds][CWAPI_WS_ShotSilent], PLATFORM_MAX_PATH-1);
            if(file_exists(fmt("sound/%s", Data[CWAPI_WD_Sounds][CWAPI_WS_ShotSilent]))) precache_sound(Data[CWAPI_WD_Sounds][CWAPI_WS_ShotSilent]);
            else if(Data[CWAPI_WD_Sounds][CWAPI_WS_ShotSilent][0]){
                log_amx("[WARNING] Sound file '%s' not found.", Data[CWAPI_WD_Sounds][CWAPI_WS_ShotSilent]);
                formatex(Data[CWAPI_WD_Sounds][CWAPI_WS_ShotSilent], PLATFORM_MAX_PATH-1, "");
            }

            json_object_get_string(Sounds, "Shot", Data[CWAPI_WD_Sounds][CWAPI_WS_Shot], PLATFORM_MAX_PATH-1);
            if(file_exists(fmt("sound/%s", Data[CWAPI_WD_Sounds][CWAPI_WS_Shot]))) precache_sound(Data[CWAPI_WD_Sounds][CWAPI_WS_Shot]);
            else if(Data[CWAPI_WD_Sounds][CWAPI_WS_Shot][0]){
                log_amx("[WARNING] Sound file '%s' not found.", Data[CWAPI_WD_Sounds][CWAPI_WS_Shot]);
                formatex(Data[CWAPI_WD_Sounds][CWAPI_WS_Shot], PLATFORM_MAX_PATH-1, "");
            }

            if(json_object_has_value(Sounds, "OnlyPrecache", JSONArray)){
                new JSON:OnlyPrecache = json_object_get_value(Sounds, "OnlyPrecache");
                
                new Temp[PLATFORM_MAX_PATH];
                for(new k = 0; k < json_array_get_count(OnlyPrecache); k++){
                    json_array_get_string(OnlyPrecache, k, Temp, PLATFORM_MAX_PATH-1);
                    if(file_exists(fmt("sound/%s", Temp))) precache_sound(Temp);
                    else log_amx("[WARNING] Sound file '%s' not found.", fmt("sound/%s", Temp));
                }

                json_free(OnlyPrecache);
            }

            json_free(Sounds);
        }

        Data[CWAPI_WD_ClipSize] = json_object_get_number(Item, "ClipSize");
        Data[CWAPI_WD_MaxAmmo] = json_object_get_number(Item, "MaxAmmo");
        Data[CWAPI_WD_Weight] = json_object_get_number(Item, "Weight");
        Data[CWAPI_WD_Price] = json_object_get_number(Item, "Price");

        Data[CWAPI_WD_MaxWalkSpeed] = json_object_get_real(Item, "MaxWalkSpeed");
        Data[CWAPI_WD_DamageMult] = json_object_get_real(Item, "DamageMult");
        Data[CWAPI_WD_Damage] = json_object_get_real(Item, "Damage");
        Data[CWAPI_WD_Accuracy] = json_object_get_real(Item, "Accuracy");
        Data[CWAPI_WD_DeployTime] = json_object_get_real(Item, "DeployTime");
        Data[CWAPI_WD_ReloadTime] = json_object_get_real(Item, "ReloadTime");
        Data[CWAPI_WD_PrimaryAttackRate] = json_object_get_real(Item, "PrimaryAttackRate");
        Data[CWAPI_WD_SecondaryAttackRate] = json_object_get_real(Item, "SecondaryAttackRate");
        Data[CWAPI_WD_HasSecondaryAttack] = json_object_get_bool(Item, "HasSecondaryAttack");

        if(!TrieKeyExists(DefWeaponsNamesList, Data[CWAPI_WD_DefaultName])){
            RegisterHam(
                Ham_Item_Deploy,
                GetWeapFullName(Data[CWAPI_WD_DefaultName]),
                "Hook_PlayerItemDeploy", true
            );
            RegisterHam(
                Ham_Item_Holster,
                GetWeapFullName(Data[CWAPI_WD_DefaultName]),
                "Hook_PlayerItemHolster", true
            );
            RegisterHam(
                Ham_Weapon_Reload,
                GetWeapFullName(Data[CWAPI_WD_DefaultName]),
                "Hook_PlayerItemReloaded", false
            );
            RegisterHam(
                Ham_CS_Item_GetMaxSpeed,
                GetWeapFullName(Data[CWAPI_WD_DefaultName]),
                "Hook_PlayerGetMaxSpeed", false
            );
            RegisterHam(
                Ham_Weapon_PrimaryAttack,
                GetWeapFullName(Data[CWAPI_WD_DefaultName]),
                "Hook_PrimaryAttack", true
            );
            RegisterHam(
                Ham_Weapon_PrimaryAttack,
                GetWeapFullName(Data[CWAPI_WD_DefaultName]),
                "Hook_PrimaryAttack_Pre", false
            );
            RegisterHam(
                Ham_Weapon_SecondaryAttack,
                GetWeapFullName(Data[CWAPI_WD_DefaultName]),
                "Hook_SecondaryAttack", true
            );
            RegisterHam(
                Ham_Weapon_Reload,
                GetWeapFullName(Data[CWAPI_WD_DefaultName]),
                "Hook_PlayerItemReloaded_Post", true
            );

            TrieSetCell(DefWeaponsNamesList, Data[CWAPI_WD_DefaultName], 0);
        }
        
        TrieSetCell(WeaponsNames, Data[CWAPI_WD_Name], ArrayPushArray(CustomWeapons, Data));

        json_free(Item);
    }while(next_file(DirHandler, File, charsmax(File), Type));

    regex_free(RegEx_FileName);
    close_dir(DirHandler);
    TrieDestroy(DefWeaponsNamesList);

    ExecuteForward(Fwds[F_LoadWeaponsPost]);
}

InitForwards(){
    Fwds[F_LoadWeaponsPost] = CreateMultiForward("CWAPI_LoadWeaponsPost", ET_IGNORE);
}

#if defined SUPPORT_RESTRICT
    public WeaponsRestrict_LoadingWeapons_Post(){
        new WeaponName[32], WeaponId, TrieIter:IterHandler;
        IterHandler = TrieIterCreate(WeaponsNames);
        while(!TrieIterEnded(IterHandler)){
            TrieIterGetKey(IterHandler, WeaponName, charsmax(WeaponName));
            TrieIterGetCell(IterHandler, WeaponId);
            TrieIterNext(IterHandler);
        }
        TrieIterDestroy(IterHandler);
        WeaponsRestrict_AddWeapon(WeaponId+WEAPONS_IMPULSE_OFFSET, WeaponName);
    }
#endif