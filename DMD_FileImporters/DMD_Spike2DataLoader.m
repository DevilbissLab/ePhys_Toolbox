function [dataStruct, status] = DMD_Spike2DataLoader(params)
% SPIKE2DATALOADER is the Spike2 File Format Data Loader
%
% Spike2DataLoader(params) returns a Struct with all the data from one
% file in a directory
%   .FileHeader
%   .data (cell array of structs) of time base (sec)
%
% PARAMS is a struct containg the necessarry fields:
%   .dataset = FileName
%   .DataChannels = {'ALL',ChannelName}
%   .EventChannel = {'ALL',ChannelName}
%
% This Function uses the SON Library.
%       Malcolm Lidierth 07/06
%       Copyright © The Author & King's College London 2006
% Located at:
% http://www.mathworks.fr/matlabcentral/fileexchange/loadFile.do?objectId=13932&objectType=File
%
% Written By David M. Devilbiss
% NexStep Biomarkers, LLC. (info@nexstepbiomarkers.com)
% October 20 2007
% Version 1.0
% Version 1.1 added error catching and new output format !
% ==========================================================================

% Initially tried using Neuro Share and Field Trip but the mex file
% couldn't deal with Digmarks so moved to SON Package and am writing my own
% import module.
status = false;
verbose = false;

% Setup cell array counters
dataIDX = 0; markerIDX = 0;
dataStruct = [];

% open file and get a list of channel names
try
    disp(['Loading File: ',params.dataset]);
    fid = fopen(params.dataset);
    if fid == -1
        disp('Cannot open data file');
        return;
    end
catch
    disp('Cannot open data file');
    return;
end

try
    ChannelNames = SONChanList(fid);

    %Add File Header to Struct
    dataStruct.FileHeader=SONFileHeader(fid);

    %walk through channels and populate struct
    for n = 1:length(ChannelNames)
        if ChannelNames(n).kind == 1 %if data channel
            % Srtfind can reurn double insted of CellArray so force to cell
            % for later ID of channel name
            %ChanCell = strfind(params.DataChannels,ChannelNames(n).title);
            ChanCell = strmatch(params.DataChannels,ChannelNames(n).title,'exact');
            if ~iscell(ChanCell)
                ChanCellArray{1} = ChanCell;
            else
                ChanCellArray = ChanCell;
            end
            
            if any(strcmpi(params.DataChannels,'ALL')) ||  any(~cellfun(@isempty,ChanCellArray))
                 %the above line is obscenly dense but finds if any are a match
                %if .DataChannels == ALL or is a match to current data channel
                [ChannelData,ChannelHeader] = SONGetChannel(fid, ChannelNames(n).number, 'scale'); %the default is Seconds which is what we want
                disp(['Loading Channel: ',ChannelNames(n).title]);
                dataIDX = dataIDX +1;
                dataStruct.data{dataIDX,1}.Header = ChannelHeader;
                dataStruct.data{dataIDX,1}.data = ChannelData;

                % Create time base for later use in trial generation
                % get TimeScale SampleInterval for use here and during marker generation
                FileTimeScale = NSB_GetSONHeaderTimescale(ChannelHeader.TimeUnits);
                FileSampleInterval = ChannelHeader.sampleinterval;
                timebase = ChannelHeader.start:(FileSampleInterval/FileTimeScale):ChannelHeader.stop;
                dataStruct.data{dataIDX,1}.time = timebase;
                
                
            else
                if verbose
                disp(['Skiping Channel: ',ChannelNames(n).title]);
                end
            end

        elseif any(strcmpi(params.EventChannel,'ALL')) || strcmpi(ChannelNames(n).title,params.EventChannel) % if there is a keyboard / digimark channel
            disp(['Loading Channel: ',ChannelNames(n).title]);
            [ChannelData,ChannelHeader] = SONGetChannel(fid, ChannelNames(n).number);
            DigiMarks = unique(ChannelData.markers(:,1));
            for m = 1:length(DigiMarks)  %this assumes only the first char is used in DigiMark
                DigiMarkIndex = find(ChannelData.markers(:,1) == DigiMarks(m));
                markerIDX = markerIDX +1;
                dataStruct.marker{markerIDX,1}.name = DigiMarks(m);
                dataStruct.marker{markerIDX,1}.TimeStamp = ChannelData.timings(DigiMarkIndex);
                % .TimeStamp is currently in seconds not on a time base
                % since that changes

                %Convert time stamps to curent time base
                % divide timings by sampint/timescale (floor to take the sample before it)
                % Now Dealt with in AEPTrialGenerator
                
                %FileTimeScale = WyethGetSONHeaderTimescale(ChannelHeader.TimeUnits);
                %FileSampleInterval = ChannelHeader.sampleinterval; %this doesn't exist in channel header !!
                %dataStruct.marker{markerIDX,1}.dataIndex = floor(dataStruct.marker{markerIDX}.TimeStamp / FileSampleInterval * FileTimeScale);
            end
        end
    end

    fclose(fid);

catch ME
    fclose(fid);
    disp('Cannot open data file:');
    disp(ME.message);
end
status = true;
