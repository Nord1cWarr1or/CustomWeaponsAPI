#include <amxmodx>
#include <reapi>
#include <cwapi>

new const ABILITY_NAME[] = "TestAbility";

public CWAPI_OnLoad() {
    new T_WeaponAbility:iAbility = CWAPI_Abilities_Register(ABILITY_NAME);
    CWAPI_Abilities_AddParams(iAbility,
        "TestString", "ShortString", true,
        "TestInteger", "Integer", true
    );

    CWAPI_Abilities_AddEventListener(iAbility, CWeapon_OnSpawn, "@OnSpawn");
    CWAPI_Abilities_AddEventListener(iAbility, CWeapon_OnSetWeaponBoxModel, "@OnSetWeaponBoxModel");
    CWAPI_Abilities_AddEventListener(iAbility, CWeapon_OnAddPlayerItem, "@OnAddPlayerItem");
    CWAPI_Abilities_AddEventListener(iAbility, CWeapon_OnDeploy, "@OnDeploy");
    CWAPI_Abilities_AddEventListener(iAbility, CWeapon_OnHolster, "@OnHolster");
}

@OnSpawn(const T_CustomWeapon:iWeapon, const ItemId, const Trie:tAbilityParams) {
    new iTestInteger;
    TrieGetCell(tAbilityParams, "TestInteger", iTestInteger);
    new sTestString[64];
    TrieGetString(tAbilityParams, "TestString", sTestString, charsmax(sTestString));

    PrintMessage(iWeapon, ItemId, "@OnSpawn(%d, %d, %d): Number = %d, String = %s", iWeapon, ItemId, tAbilityParams, iTestInteger, sTestString);
}

@OnSetWeaponBoxModel(const T_CustomWeapon:iWeapon, const iWeaponBox, const ItemId, const Trie:tAbilityParams) {
    new iTestInteger;
    TrieGetCell(tAbilityParams, "TestInteger", iTestInteger);
    new sTestString[64];
    TrieGetString(tAbilityParams, "TestString", sTestString, charsmax(sTestString));

    PrintMessage(iWeapon, ItemId, "@OnSetWeaponBoxModel(%d, %d, %d, %d): Number = %d, String = %s", iWeapon, iWeaponBox, ItemId, tAbilityParams, iTestInteger, sTestString);
}

@OnAddPlayerItem(const T_CustomWeapon:iWeapon, const ItemId, const UserId, const Trie:tAbilityParams) {
    new iTestInteger;
    TrieGetCell(tAbilityParams, "TestInteger", iTestInteger);
    new sTestString[64];
    TrieGetString(tAbilityParams, "TestString", sTestString, charsmax(sTestString));

    PrintMessage(iWeapon, ItemId, "@OnAddPlayerItem(%d, %d, %n, %d): Number = %d, String = %s", iWeapon, ItemId, UserId, tAbilityParams, iTestInteger, sTestString);
}

@OnDeploy(const T_CustomWeapon:iWeapon, const ItemId, const Trie:tAbilityParams) {
    new iTestInteger;
    TrieGetCell(tAbilityParams, "TestInteger", iTestInteger);
    new sTestString[64];
    TrieGetString(tAbilityParams, "TestString", sTestString, charsmax(sTestString));

    PrintMessage(iWeapon, ItemId, "@OnDeploy(%d, %d, %d): Number = %d, String = %s", iWeapon, ItemId, tAbilityParams, iTestInteger, sTestString);
}

@OnHolster(const T_CustomWeapon:iWeapon, const ItemId, const Trie:tAbilityParams) {
    new iTestInteger;
    TrieGetCell(tAbilityParams, "TestInteger", iTestInteger);
    new sTestString[64];
    TrieGetString(tAbilityParams, "TestString", sTestString, charsmax(sTestString));

    PrintMessage(iWeapon, ItemId, "@OnHolster(%d, %d, %d): Number = %d, String = %s", iWeapon, ItemId, tAbilityParams, iTestInteger, sTestString);
}

PrintMessage(const T_CustomWeapon:iWeapon, const ItemId, const sMsg[], const any:...) {
    new UserId = get_member(ItemId, m_pPlayer);

    new sFmtMsg[256];
    vformat(sFmtMsg, charsmax(sFmtMsg), sMsg, 4);

    if (UserId > 0) {
        client_print(UserId, print_chat, "[TEST] [%n, %s] %s", UserId, CWAPI_Weapons_iGetName(iWeapon), sFmtMsg);
        client_print(UserId, print_console, "[TEST] [%n, %s] %s", UserId, CWAPI_Weapons_iGetName(iWeapon), sFmtMsg);
        server_print("[TEST] [%n, %s] %s", UserId, CWAPI_Weapons_iGetName(iWeapon), sFmtMsg);
    } else {
        server_print("[TEST] [%s] %s", CWAPI_Weapons_iGetName(iWeapon), sFmtMsg);
    }
}