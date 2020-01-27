--
-- <summary>
-- 	  This script reads a PosiStageNet tracker stream from UDP Multicast
-- </summary>
-- <param name="name" default="AVIO-PosiStageNet">Port name</param>
--
-- <author>David Stone, ShadowControls</author>
require("avio")
require("socket")

local PSN_INFO_PACKET = 0x6756
local PSN_DATA_PACKET = 0x6755
local PSN_V1_INFO_PACKET = 0x503c
local PSN_V1_DATA_PACKET = 0x6754

local BASE_CHUNK_IDS = {
    [PSN_INFO_PACKET] = "PSN_V2_INFO_PACKET",
    [PSN_DATA_PACKET] = "PSN_V2_DATA_PACKET",
    [PSN_V1_INFO_PACKET] = "PSN_V1_INFO_PACKET",
    [PSN_V1_DATA_PACKET] = "PSN_V1_DATA_PACKET",
}

local PSN_INFO_PACKET_HEADER = 0x0000
local PSN_INFO_SYSTEM_NAME = 0x0001
local PSN_INFO_TRACKER_LIST = 0x0002

local INFO_CHUNK_IDS = {
    [PSN_INFO_PACKET_HEADER] = "PSN_INFO_PACKET_HEADER",
    [PSN_INFO_SYSTEM_NAME] = "PSN_INFO_SYSTEM_NAME",
    [PSN_INFO_TRACKER_LIST] = "PSN_INFO_TRACKER_LIST",
}

local PSN_DATA_PACKET_HEADER = 0x0000
local PSN_DATA_TRACKER_LIST = 0x0001

local DATA_CHUNK_IDS = {
    [PSN_DATA_PACKET_HEADER] = "PSN_DATA_PACKET_HEADER",
    [PSN_DATA_TRACKER_LIST] = "PSN_DATA_TRACKER_LIST",
}

local PSN_INFO_TRACKER_NAME = 0x0000
local TRACKER_LIST_CHUNK_IDS = {
    [PSN_INFO_TRACKER_NAME] = "PSN_INFO_TRACKER_NAME"
}

local PSN_DATA_TRACKER_POS = 0x0000
local PSN_DATA_TRACKER_SPEED = 0x0001
local PSN_DATA_TRACKER_ORI = 0x0002
local PSN_DATA_TRACKER_STATUS = 0x0003
local PSN_DATA_TRACKER_ACCEL = 0x0004
local PSN_DATA_TRACKER_TRGTPOS = 0x0005
local PSN_DATA_TRACKER_TIMESTAMP = 0x0006

local TRACKER_CHUNK_IDS = {
    [PSN_DATA_TRACKER_POS] = "PSN_DATA_TRACKER_POS",
    [PSN_DATA_TRACKER_SPEED] = "PSN_DATA_TRACKER_SPEED",
    [PSN_DATA_TRACKER_ORI] = "PSN_DATA_TRACKER_ORI",
    [PSN_DATA_TRACKER_STATUS] = "PSN_DATA_TRACKER_STATUS",
    [PSN_DATA_TRACKER_ACCEL] = "PSN_DATA_TRACKER_ACCEL",
    [PSN_DATA_TRACKER_TRGTPOS] = "PSN_DATA_TRACKER_TRGTPOS",
    [PSN_DATA_TRACKER_TIMESTAMP] = "PSN_DATA_TRACKER_TIMESTAMP",
}



_ip = "";
_port = "";
_udp = nil;

_doReceive = false;
_readMessage = "";
_isOpen = false;
_lastConnectedState = false;
_isServer = false;

trackerNum = 0

function init(name, ipPort)
	avio.addPort(name,"This port represents a PSN connection", "event");

	local var = split(ipPort, ":");
	_ip = var[1];
	_port = var[2];

	avio.addChannel(name,"ServerName","string");
	avio.addChannel(name,"TrackerNo","string");
  avio.addChannel(name,"pos_x","string");
  avio.addChannel(name,"pos_y","string");
  avio.addChannel(name,"pos_z","string");
	avio.addChannel(name,"clientIp","string");
	avio.addChannel(name,"status","string");
	avio.addChannel(name,"connected",1);

	avio.setFunction("connectedChanged", "connected");
  avio.setFunction("trackerChanged", "TrackerNo");
	avio.setChannel("status", "ready");

	avio.setChannel("connected", 0)
  avio.setChannel("TrackerNo", 0)
  avio.setChannel("ServerName", "");
	avio.setPeriodicFunction("interrupt", 1);
end

function split(p, d) -- string, separator
   local t, ll
   t={}
   ll=0
   if(#p == 1) then
      return {p}
   end
   while true do
      l = string.find(p, d, ll, true) -- find the next d in the string
      if l ~= nil then -- if "not not" found then..
         table.insert(t, string.sub(p,ll,l-1)) -- Save it in our array.
         ll = l + 1 -- save just after where we found it for searching next time.
      else
         table.insert(t, string.sub(p,ll)) -- Save what's left in our array.
         break -- Break at end, as it should be, according to the lua manual.
      end
   end
   return t
end

function endsWith(str, ending)
	if(str:len() < ending:len()) then
		return false;
	end
	local currEnding = str:sub(-ending:len());
	return (currEnding == ending);
end

function closed()
	if(_isOpen) then
		_isOpen = false;
		_doReceive = false;
		avio.setChannel("status", "Connection closed");
	end
end

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

function interrupt()
	if(_doReceive) then
		local cont = true;
    local length = 0

		local val, otherIp, otherPort = _udp:receivefrom(1500);

		if(val ~= nil) then
			--avio.setChannel("udpInput", val);
			avio.setChannel("clientIp", otherIp);


      if u16(val,0) == PSN_INFO_PACKET then
        --avio.setChannel("udpInput", "Info Packet");
        if u16(val,4) == PSN_INFO_PACKET_HEADER then
          length = u16(val,22)
          --if u16(val,length+8) == PSN_INFO_SYSTEM_NAME then
          local tmpString = ""
          for l=0,length-1,1 do
            tmpString = (tmpString .. c8(val,25+l) )
          end
          avio.setChannel("ServerName", tmpString) --SystemNameChunk

      end
        --avio.setChannel("udpInput", u16(val,0));
      end
      if u16(val,0) == PSN_DATA_PACKET then
        --avio.setChannel("udpInput", "Info Packet");
        if u16(val,4) == PSN_DATA_PACKET_HEADER then
          length = u16(val,6)
          if length > 32768 then --Has subchunks
            length = length-32768
          end
            if u16(val,length+8) == PSN_DATA_TRACKER_LIST then

              if u16(val,length+8+4) == 0x0000 then
                if u16(val,length+8+4+4) == PSN_DATA_TRACKER_POS then

                  avio.setChannel("pos_x", convertfloat(string.sub(val,length+16+((trackerNum+1)*4)+1,length+16+((trackerNum+4)*4)+1 +4)))
                  avio.setChannel("pos_y", convertfloat(string.sub(val,length+16+((trackerNum+1)*4)+5,length+16+((trackerNum+4)*4)+5 +4)))
                  avio.setChannel("pos_z", convertfloat(string.sub(val,length+16+((trackerNum+1)*4)+9,length+16+((trackerNum+4)*4)+9 +4)))
              end
            end
            --avio.setChannel("udpInput", convertfloat(string.sub(val,53,53 +4)))
          end


          --avio.setChannel("udpInput", length)
          --local systemName = ''
          --for
          --avio.setChannel("udpInput", "Info Packet Header")
          --avio.setChannel("udpInput", u64(val,8)); --Timestamp
          --avio.setChannel("udpInput", length) --Chunk Length
          --avio.setChannel("udpInput", u16(val,2));
        --end

      end
        --avio.setChannel("udpInput", u16(val,0));
      end



			--p_psn.dissector (val, root);

			if(_isServer) then
				_otherIp = otherIp;
				_otherPort = otherPort;
			end
		else
			----Not displaying timeout
			if(otherIp ~= "timeout") then
				avio.setChannel("status", otherIp);
			end
		end
	end
end


--Takes 4x bits and converts them in reverse order to a Float32
function convertfloat(str)
  -- Change to b4,b3,b2,b1 to unpack an LSB float
  local b4,b3,b2,b1 = string.byte(str,1,4)

  local exponent = (b1 % 128) * 2 + math.floor(b2 / 128)
  if exponent == 0 then return 0 end
  local sign = (b1 > 127) and -1 or 1
  local mantissa = ((b2 % 128) * 256 + b3) * 256 + b4
  mantissa = (math.ldexp(mantissa, -23) + 1) * sign
  return math.ldexp(mantissa, exponent - 127)
end

function trackerChanged(val)
  trackerNum = val

end

function connectedChanged(val)
	if(val >= 1) then
		if(_isOpen == false) then
			avio.setChannel("status", "Initializing...");
			_udp = assert(socket.udp());
			assert(_udp:setoption("ip-add-membership", {multiaddr = "236.10.10.10", interface = "*"}));
			_udp:settimeout(0.5);
			if(_ip == "") then
				_udp:setsockname("*",_port)
				_doReceive = true;
				_isOpen = true;
				_isServer = true;
				avio.setChannel("status", "Receiving");
			else
				_udp:setsockname("*",0)
				_doReceive = true;
				_isOpen = true;
				_isServer = false;
				avio.setChannel("status", "Ready");
			end
		end
	else
		if(_isOpen) then
			avio.setChannel("Disconnecting...");
			_udp:close();
			closed();
		end
	end

end

function u8(b, i)
  return string.byte(b, i+1)
end

function c8(b, i)
  local stringTmp = string.char(string.byte(b, i))
  return stringTmp
end
--- Get a 16-bit integer at a 0-based byte offset in a byte string.
-- @param b A byte string.
-- @param i Offset.
-- @return A 16-bit integer.
function u16(b, i)
  local b1,b2
  b1, b2 = string.byte(b, i+1), string.byte(b, i+2)
  --        2^8     2^0
  return b2*256 + b1
end
--- Get a 32-bit integer at a 0-based byte offset in a byte string.
-- @param b A byte string.
-- @param i Offset.
-- @return A 32-bit integer.
function u32(b,i)
  local b1,b2,b3,b4
  b1, b2 = string.byte(b, i+1), string.byte(b, i+2)
  b3, b4 = string.byte(b, i+3), string.byte(b, i+4)
  --        2^24          2^16       2^8     2^0
  return b4*16777216 + b3*65536 + b2*256 + b1
end
function u64(b,i)
  local b1,b2,b3,b4,b5,b6,b7,b8
  b1, b2 = string.byte(b, i), string.byte(b, i+1)
  b3, b4 = string.byte(b, i+2), string.byte(b, i+3)
  b5, b6 = string.byte(b, i+4), string.byte(b, i+5)
  b7, b8 = string.byte(b, i+6), string.byte(b, i+7)
  --        2^24          2^16       2^8     2^0
  return b8*281474976710656*256 + b7*281474976710656 + b6*1099511627776 + b5*4294967296 + b4*16777216 + b3*65536 + b2*256 + b1
end
