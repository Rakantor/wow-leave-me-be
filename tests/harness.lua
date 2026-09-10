LMB = {}
NOW = 10
TIMERS = {}
FRAMES = {}
FILTERS = {}
SENT = {}
FRIENDS = {}
ADDS = {}
REMOVES = {}
DISPLAYED = {}
SECRETS = {}
LISTED = false
GROUPED = false
LEADER = false
LE_PARTY_CATEGORY_HOME = 1
ERR_FRIEND_LIST_FULL = 'Your friends list is full.'
ERR_FRIEND_ADDED_S = '%s added to friends.'
ERR_FRIEND_REMOVED_S = '%s removed from friends.'
ERR_FRIEND_ALREADY_S = '%s is already your friend.'
ERR_FRIEND_ONLINE_SS = '|Hplayer:%s|h[%s]|h has come online.'
ERR_FRIEND_OFFLINE_S = '%s has gone offline.'
ERR_FRIEND_NOT_FOUND = 'Player not found.'
PRINTED = {}
MODE = 'inline'
LEGACY_FRIENDS_ENABLED = true
WINDOWS = {}
CLOSED_WINDOWS = {}
function GetCVar() return MODE end
function hooksecurefunc(name, hook)
 local original = _G[name]
 _G[name] = function(...)
  local results = {original(...)}
  hook(...)
  return unpack(results)
 end
end
function issecretvalue(value) return SECRETS[value] == true end
function wipe(tbl) for k in pairs(tbl) do tbl[k] = nil end end
function GetTime() return NOW end
function time() return 100000 + NOW end
function GetNormalizedRealmName() return 'HomeRealm' end
function UnitName() return 'Tester' end
function UnitFullName() return 'Tester', 'HomeRealm' end
function UnitGUID() return nil end
function IsInRaid() return false end
function IsInGroup() return GROUPED end
function UnitIsGroupLeader() return LEADER end
function GetNumGroupMembers() return 0 end
function GetNumSubgroupMembers() return 0 end
function IsGuildMember() return false end
function MuteSoundFile() end
function UnmuteSoundFile() end
function Ambiguate(name, mode) return (name:gsub('%-HomeRealm$', '')) end
function CreateFrame(kind,name,parent,template)
 local f={events={},scripts={},name=name}
 function f:RegisterEvent(event) self.events[event]=true end
 function f:SetScript(event,fn) self.scripts[event]=fn end
 function f:GetScript(event) return self.scripts[event] end
 function f:HookScript(event,fn)
  local original = self.scripts[event]
  self.scripts[event] = function(...)
   if original then original(...) end
   fn(...)
  end
 end
 function f:GetNumMessages() return #(self.messages or {}) end
 function f:UnregisterEvent(event) self.events[event]=nil end
 function f:GetName() return self.name end
 function f:IsForbidden() return false end
 FRAMES[#FRAMES+1]=f
 return f
end
function Emit(event,...)
 local listeners={}
 for _,f in ipairs(FRAMES) do if f.events[event] then listeners[#listeners+1]=f end end
 for _,f in ipairs(listeners) do
  if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end
 end
end
function Advance(seconds)
 local target=NOW+seconds
 while true do
  local nextIndex,deadline
  for i,timer in ipairs(TIMERS) do
   if timer.at<=target and (not deadline or timer.at<deadline) then
    nextIndex,deadline=i,timer.at
   end
  end
  if not nextIndex then break end
  NOW=deadline
  local timer=table.remove(TIMERS,nextIndex)
  timer.fn()
 end
 NOW=target
end
C_Timer={After=function(delay,fn) TIMERS[#TIMERS+1]={at=NOW+delay,fn=fn} end}
C_AutoComplete={GetAutoCompleteRealms=function() return {'HomeRealm','ConnectedRealm'} end}
C_BattleNet={GetGameAccountInfoByGUID=function() return nil end}
C_LFGList={HasActiveEntryInfo=function() return LISTED end}
C_ChatInfo={SendChatMessage=function(message,kind,language,target)
 SENT[#SENT+1]={message=message,target=target}
end}
C_FriendList={
 IsLegacyFriendSystemEnabled=function() return LEGACY_FRIENDS_ENABLED end,
 GetNumFriends=function() return #FRIENDS end,
 GetFriendInfo=function(name)
  for _,f in ipairs(FRIENDS) do if f.name==name then return f end end
 end,
 GetFriendInfoByIndex=function(index) return FRIENDS[index] end,
 IsFriend=function(guid)
  for _,f in ipairs(FRIENDS) do if f.guid==guid then return true end end
  return false
 end,
 AddFriend=function(name,note) ADDS[#ADDS+1]={name=name,note=note} end,
 RemoveFriendByIndex=function(index)
  REMOVES[#REMOVES+1]=table.remove(FRIENDS,index)
 end,
 ShowFriends=function() end,
}
ChatFrameUtil={AddMessageEventFilter=function(event,fn) FILTERS[event]=fn end}
DEFAULT_CHAT_FRAME={AddMessage=function(_,message) PRINTED[#PRINTED+1]=message end, IsForbidden=function() return false end}
SlashCmdList={}
function GetFramesRegisteredForEvent(event)
 local found={}
 for _,f in ipairs(FRAMES) do if f.events[event] then found[#found+1]=f end end
 return unpack(found)
end
CHAT=CreateFrame('Frame','ChatFrame1')
CHAT:RegisterEvent('CHAT_MSG_WHISPER')
function CHAT:MessageEventHandler(event,...)
 if issecretvalue(...) or not FILTERS[event](self,event,...) then
  self.messages=self.messages or {}
  self.messages[#self.messages+1]={...}
  DISPLAYED[#DISPLAYED+1]={...}
 end
end
LINE_ID=0
function Whisper(sender,guid,message)
 LINE_ID=LINE_ID+1
 Emit('CHAT_MSG_WHISPER',message or 'hello',sender,'Common','','','',0,0,'',0,LINE_ID,guid,0,false,false,false,false,{})
end
function Resolve(sender,guid,level)
 FRIENDS[#FRIENDS+1]={name=sender,guid=guid,level=level,notes='LeaveMeBe:level-check'}
 Emit('FRIENDLIST_UPDATE')
end
function Expect(condition,message) assert(condition,message) end

CHAT:SetScript('OnEvent', CHAT.MessageEventHandler)
SELECTED_DOCK_FRAME=DEFAULT_CHAT_FRAME
function FCF_SelectDockFrame(frame) SELECTED_DOCK_FRAME=frame end
function FCF_SetTemporaryWindowType(frame,chatType,target)
 frame.chatType=chatType
 frame.chatTarget=target
end
function FCF_OpenTemporaryWindow(chatType,target)
 local frame=CreateFrame('Frame','ChatFrame'..(#WINDOWS+10))
 frame.isTemporary=true
 frame.inUse=true
 frame.messages={}
 frame.MessageEventHandler=CHAT.MessageEventHandler
 frame:SetScript('OnEvent',frame.MessageEventHandler)
 frame:RegisterEvent('CHAT_MSG_WHISPER')
 frame:RegisterEvent('CHAT_MSG_WHISPER_INFORM')
 WINDOWS[#WINDOWS+1]=frame
 FCF_SetTemporaryWindowType(frame,chatType,target)
 return frame
end
function FCFManager_GetNumDedicatedFrames(chatType,target)
 local count=0
 for _,frame in ipairs(WINDOWS) do
  if frame.inUse and frame.chatType==chatType and frame.chatTarget==target then count=count+1 end
 end
 return count
end
function FCF_Close(frame)
 frame.inUse=false
 frame:UnregisterEvent('CHAT_MSG_WHISPER')
 frame:UnregisterEvent('CHAT_MSG_WHISPER_INFORM')
 CLOSED_WINDOWS[#CLOSED_WINDOWS+1]=frame
end
FloatingChatFrameManager=CreateFrame('Frame','FloatingChatFrameManager')
FloatingChatFrameManager:RegisterEvent('CHAT_MSG_WHISPER')
FloatingChatFrameManager:RegisterEvent('CHAT_MSG_WHISPER_INFORM')
-- Model Blizzard's documented ordering: create the window first, then pass
-- the event to its message handler (and therefore to the message filters).
FloatingChatFrameManager:SetScript('OnEvent',function(_,event,...)
 local sender=select(2,...)
 if MODE~='inline' and FCFManager_GetNumDedicatedFrames('WHISPER',sender)==0 then
  local frame=FCF_OpenTemporaryWindow('WHISPER',sender)
  frame:GetScript('OnEvent')(frame,event,...)
  if event=='CHAT_MSG_WHISPER_INFORM' then FCF_SelectDockFrame(frame) end
 end
end)
function Initialize()
 LMB.RegisterOptions=function() end
 LMB:Initialize()
 Advance(0)
 LeaveMeBeDB.blockAllWhispers=true
end
