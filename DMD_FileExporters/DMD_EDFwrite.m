function [ret, msg] = DMD_EDFwrite(DataStruct, options)
%
%
% Inputs
%   DataStruct
%   options
%       .SaveDir - Path to save .edf
%       .SaveFilename - Filename to save .edf (optional)
%       .edfType - 0 = edf, 1 = edf+ (optional default = 1)
%
% "The Physical min of sig 5 is invalid
% "Samples per record of Sig 1 is less than 1

try
ret = false; msg = '';
HDR.labels = cell(0);HDR.digmin = []; HDR.digmax = []; HDR.physmin = []; HDR.physmax =[];
data = [];
defaultData = 'X';
[filePath,fileName,fileExt] = fileparts(DataStruct.Filename);

if nargin < 2
    options = struct();
end
if ~isfield(options,'SaveDir')
    options.SaveDir = fullfile(filePath, 'converted');
end
%Create folder if none exists
if exist(options.SaveDir,'dir') ~= 7
    mkdir(options.SaveDir);
end

if ~isfield(options,'SaveFilename')
    saveFileName = fullfile(options.SaveDir, [fileName,'.edf']);
else
    saveFileName = fullfile(options.SaveDir, options.SaveFilename);
end


%% Build Header for SaveEDF
% Note .plx data does not store most of these
HDR.patient.ID  = defaultData;
HDR.patient.Sex = defaultData;
HDR.patient.BirthDate = defaultData;
HDR.patient.Name = regexprep(fileName,'\s','_'); %cannnot have spaces and use file name since no data is aval
HDR.record.ID = defaultData;
HDR.record.Tech = defaultData;
%HDR.record.Eq = regexprep(['Cerora_',DataStruct.HeadSetModel{1},'_',DataStruct.sernum],'\s','_');
HDR.record.Eq = ['Plexon_ver',num2str(DataStruct.Version)];
try
    HDR.startdate = datestr(datenum(DataStruct.StartDate),1);
    HDR.starttime = datestr(datenum(DataStruct.StartDate),13);
catch
    HDR.startdate = 'X';
    HDR.starttime = [];
end
HDR.fileDuration = DataStruct.nSeconds;
HDR.duration = 1;                       %This is the signal block duration in seconds, default =1
HDR.labels = {DataStruct.Channel(:).Name};
HDR.transducer = ' ';
HDR.units = {DataStruct.Channel(:).Units};
HDR.prefilt  = 'HP:0.5Hz LP:100Hz N:60Hz';

HDR.samplerate = [DataStruct.Channel(:).Hz];

%Because Plexon and Nex data are in mV not ADC values we need to back
%convert using a 16-bit ADC approach.
HDR.physmax = 1;
HDR.physmin = -1;
HDR.digmax = 32767;
HDR.digmin = -32768;

%% Build Annotations for header
    HDR.annotation.starttime = [];
    HDR.annotation.duration = [];
    HDR.annotation.event = {};
for curEvent = 1:length(DataStruct.events)
    HDR.annotation.starttime = [HDR.annotation.starttime; DataStruct.events(curEvent).ts];
    HDR.annotation.duration = [HDR.annotation.duration; zeros(length(DataStruct.events(curEvent).ts),1)];
    HDR.annotation.event = [HDR.annotation.event; cellstr(repmat(DataStruct.events(curEvent).Name,length(DataStruct.events(curEvent).ts),1))];
end
%Note this may need to be sorted but I don't think so.

%% Build data array
%if the sample rate and lengths are the same then concatinate
if isfield(DataStruct.Channel, 'nSamples')
    nSamples = [DataStruct.Channel(:).nSamples];
elseif isfield(DataStruct.Channel, 'NPointsWave')
    nSamples = [DataStruct.Channel(:).NPointsWave];
else
    nSamples = [];
    for curChan = 1:length(DataStruct.Channel)
    nSamples = [nSamples, length(DataStruct.Channel(:).Data)];
    end
end
if length(unique(HDR.samplerate)) == 1 && length(unique(nSamples)) == 1
    Data = [DataStruct.Channel(:).Data];
else
    Data = {DataStruct.Channel(:).Data};
end

%clear DataStruct;                   %this is optional
%Transform the Data into ADC values
Data = round(Data / (2/65535));

    [ret, msg] = SaveEDF(saveFileName, Data, HDR);
    ret = true;
catch ME
    msg = [ME.message,' in ',ME.stack(1).name,' Line: ',num2str(ME.stack(1).line)];
end
