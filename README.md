# [NMRiH] Dimension Time Drops
Tossable cash and perks for [Dimension Time](https://steamcommunity.com/sharedfiles/filedetails/?id=2489653968)

![image](https://user-images.githubusercontent.com/11559683/126886527-0de25f5f-83d2-4781-8f63-4a87c104bb33.png)

### Features
- Perks and cash can be dropped and picked up by other players

  - Type `/dim` to access the drop menu

    ![droppreview](https://user-images.githubusercontent.com/11559683/126886592-f478a341-621d-416b-a278-95554fb31be7.png) 

  - Or press the drop key (Default: `G`) with your fists equipped to drop a cash bundle (1 point each)

- Perks and cash are dropped on death instead of vanishing

  ![image](https://user-images.githubusercontent.com/11559683/126886569-2c832052-c938-42ca-9b8c-63a57b6e8a60.png)

### Planned
- Direct item transfers.

### ConVars
- `dim_item_despawn_time` (Default: `50`)
  - Dropped items will despawn after this many seconds.
  
  A config file is automatically generated in `cfg/sourcemod`.

### Commands

- `sm_dim`
  - Access the drop menu. 

### Admin/Debug Commands
- `sm_dim_dropall <#userid|name>`
  - Force a client to drop all of their cash/perks.
- `sm_dim_stats <#userid|name>`  
  - See a client's owned perks and cash.
- `sm_dim_giveall`
  - Spawn all perks and cash required to max out your character.
