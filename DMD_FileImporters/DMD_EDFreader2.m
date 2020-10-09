function [DataStruct, status, msg] = NSB_EDFreader2(filename,options)
% NSB_EDFreader() - EDF and EDF+ reader
%
% Inputs:
%   filename          - (string) Path+FileName of Existing file
%   options           - (struct) of options
%                           options.logfile
%                           options.chans (not implemented)
%                           options.progress (not implemented)
%
% Outputs:
%   DataStruct          - (struct) NSB DataStructure
%   status              - (logical) return value
%   msg                 - (string) error message 
%
% See also:
%   http://www.edfplus.info/specs/edfplus.html
%
% Dependencies: 
% NSBlog
%
% Validated. Same read as Spike 2 and NeuroScore
% 
%
% Written By David M. Devilbiss
% NexStep Biomarkers, LLC. (info@nexstepbiomarkers.com)
% December 8 2011, Version 1.0
% Feb 21 2012, Version 1.1 Fix for nRecords
% Oct 11 2016, Version 2.0 now fread is a single block read
% ToDo: add edf+ spec and annotations.


status = false; msg = '';
switch nargin
    case 0
        [filename,filepath] = uigetfile({'*.rec;*.edf','European Data Format (*.edf,*.rec)';},'Select an EDF file...');
        filename = fullfile(filepath,filename);
        options.logfile = '';
        options.chans = [];
        options.progress = true;
    case 1
        options.logfile = '';
        options.chans = [];
        options.progress = true;
        %set default options
        %log file
        %chan read vector
        %progress Bar
    case 2
        %check otptions
end
if exist(filename,'file') ~= 2
    DataStruct = [];
    errorstr = ['ERROR: NSB_EDFreader >> File does not exist: ',filename];
        if ~isempty(options.logfile)
            status = DMD_logger(options.logfile,errorstr);
        else
            msg = errorstr;
        end
    return;
end

try
fid = fopen(filename,'r','ieee-le');
    if fid < 0
        DataStruct = [];
        errorstr = ['ERROR: NSB_EDFreader >> Cannot open: ',filename];
        if ~isempty(options.logfile)
            status = DMD_logger(options.logfile,errorstr);
        else
            msg = errorstr;
        end
        fclose(fid);
        return;
    end

%read header as block
HDR = char(fread(fid,256,'uchar')');

%Parse header
%edf data format
DataStruct.Version = str2double(HDR(1:8));

%patientID field
% can be further parsed into
% 1) Subject Code, 2) gender, 3) birthdate in dd-MMM-yyyy, 4) Subject Name, 5) other Subfields
patientID = strtrim( char(HDR(9:88)) );
patientID = regexp(patientID,'\s','split'); 
% Many preclinical edf writers do no follow the specifications and make up
% their own rules for this field.
patientIDFields = {'SubjectID', 'Gender', 'BirthDate', 'SubjectName', 'patientIDoptinal1', 'patientIDoptinal2'};
for curField = 1:length(patientID)
    DataStruct.(patientIDFields{curField}) = patientID{curField};
end
%Later the SubjectID will be used to write a file name. It cannot contain '\' or :\ in it
% if it does contain "tanks in it"
illegalCharsPat = ['(\',filesep,')|(:\',filesep,')'];
DataStruct.SubjectID = regexprep(DataStruct.SubjectID, illegalCharsPat, '-');
DataStruct.SubjectID = regexprep(DataStruct.SubjectID, '[<>:|?*_]', '');

% recordID field
% can be further parsed into
% 1) text 'Startdate', 2) dd-MMM-yyyy, 3) administration code UID, 4) technician, 5) equipment used, 6) other Subfields
% Many preclinical edf writers do no follow the specifications and make up
% their own rules for this field.
recordIDfield = strtrim( char(HDR(89:168)) );
recordIDFields = {'StartdateTXT', 'StartDate', 'AdminUID', 'Technician', 'Equipment', 'recordIDoptinal1', 'recordIDoptinal2'};
DataStruct.Comment = recordIDfield;
recordIDfield = regexp(recordIDfield,'\s','split');
if ~isempty(recordIDfield)
    if strcmpi(recordIDfield{1},'Startdate') 
for curField = 1:length(recordIDfield)
    DataStruct.(recordIDFields{curField}) = recordIDfield{curField};
end
    else
        %Badly written recordID field
        DataStruct.Technician = [];
    end
else
    %Badly written recordID field
    DataStruct.Technician = [];
end

% startdate and starttime 
DataStruct.StartDate = datenum([char(HDR(169:176)),'.',(HDR(177:184))],'dd.mm.yy.HH.MM.SS');
% number of bytes in header record
DataStruct.HeaderLength = str2double(HDR(185:192));
% reserved (empty for edf, filled if other edf varient)
FileFormat = strtrim( HDR(193:236) );
if isempty(FileFormat)
    DataStruct.FileFormat = '.edf';
else
    DataStruct.FileFormat = FileFormat; %This would indicate EDF+
end

DataStruct.nRecords = str2num (HDR(237:244));
DataStruct.RecordnSeconds = str2num (HDR(245:252));
DataStruct.nSeconds = DataStruct.RecordnSeconds * DataStruct.nRecords; %total length
DataStruct.nChannels = str2num (HDR(253:256));

%calculate size of signal header
SigHDRSize = DataStruct.HeaderLength - 256;
%Read Signal Header
HDR = char(fread(fid,SigHDRSize,'uchar')');

%For each channel populate subheader
%get Channel Names (labels = 16 ascii * nChannels)
HDRoffset = 0;
fieldSize = 16;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).Name = strtrim(char( HDR(StartIDX:EndIDX) ));
    DataStruct.Channel(curCell,1).Name = regexprep(DataStruct.Channel(curCell,1).Name, '_', '-'); %Do not allow underscores!
end
HDRoffset = EndIDX;

%Generate Channel Number
for curCell = 1:DataStruct.nChannels
    DataStruct.Channel(curCell,1).ChNumber = curCell; 
end

%get electrodetype (transducer type = 80 ascii * nChannels)
fieldSize = 80;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).Transducer = strtrim(char( HDR(StartIDX:EndIDX) )); 
end
HDRoffset = EndIDX;

%get dimension label (8 ascii * nChannels)
fieldSize = 8;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).Units = strtrim(char( HDR(StartIDX:EndIDX) )); 
end
HDRoffset = EndIDX;

%get phys Min (8 ascii * nChannels)
fieldSize = 8;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).PhysMin = str2double( strtrim(char( HDR(StartIDX:EndIDX) )) );
end
HDRoffset = EndIDX;

%get phys Max (8 ascii * nChannels)
fieldSize = 8;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).PhysMax = str2double( strtrim(char( HDR(StartIDX:EndIDX) )) );
end
HDRoffset = EndIDX;

%get dig Min (8 ascii * nChannels)
fieldSize = 8;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).DigMin = str2double( strtrim(char( HDR(StartIDX:EndIDX) )) );
end
HDRoffset = EndIDX;

%get dig Max (8 ascii * nChannels)
fieldSize = 8;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).DigMax = str2double( strtrim(char( HDR(StartIDX:EndIDX) )) );
end
HDRoffset = EndIDX;

%get pre-Filtering (80 ascii * nChannels)
fieldSize = 80;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).PreFilter = strtrim(char( HDR(StartIDX:EndIDX) )); 
end
HDRoffset = EndIDX;

%get nSamples in each data record (8 ascii * nChannels)
fieldSize = 8;
for curCell = 1:DataStruct.nChannels
    StartIDX = (curCell-1)*fieldSize+1 +HDRoffset;
    EndIDX = curCell*fieldSize +HDRoffset;
    DataStruct.Channel(curCell,1).RecordnSamples = str2double( strtrim(char( HDR(StartIDX:EndIDX) )) );%SamplesPer Record
end
HDRoffset = EndIDX;

%Calculate Hz
for curCell = 1:DataStruct.nChannels
    %this is wrong for categorical data!!!
    DataStruct.Channel(curCell,1).Hz = DataStruct.Channel(curCell,1).RecordnSamples/DataStruct.RecordnSeconds;
end

%read data as a block
DATA = fread(fid,'int16'); % Loading of signals
%waitbar may be nice here << can read 24h of 3 ch 500Hz in 9 seconds
%also, what if there is not enough memory?
fclose(fid); % close a file

%Shape data into records
% DataStruct.nRecords is only -1 if data is still streaming
DATA=reshape(DATA, [], DataStruct.nRecords);

StartIDX = 1;
EndIDX = 0;
for curCell = 1:DataStruct.nChannels
    EndIDX = DataStruct.Channel(curCell).RecordnSamples +StartIDX-1;
    DataStruct.Channel(curCell,1).Data = DATA(StartIDX:EndIDX,:);
    % serialize
    DataStruct.Channel(curCell,1).Data = DataStruct.Channel(curCell,1).Data(:);
    %scale to physical units (only if analog channel)
    if doScaling(DataStruct.Channel(curCell,1).Units)
    DataStruct.Channel(curCell,1).Data = (DataStruct.Channel(curCell,1).Data - DataStruct.Channel(curCell,1).DigMin) / (DataStruct.Channel(curCell,1).DigMax - DataStruct.Channel(curCell,1).DigMin);
    DataStruct.Channel(curCell,1).Data = DataStruct.Channel(curCell,1).Data .* double(DataStruct.Channel(curCell,1).PhysMax - DataStruct.Channel(curCell,1).PhysMin) + DataStruct.Channel(curCell,1).PhysMin;
    %Remove DC offset (mean)
    DataStruct.Channel(curCell,1).Data = DataStruct.Channel(curCell,1).Data-mean(DataStruct.Channel(curCell,1).Data);
    end
    StartIDX = EndIDX +1;
end

AnnotationsIDX = find(strcmpi({DataStruct.Channel.Name},'EDF Annotations'));
%handle EDF+ annotations here


catch ME
        errorstr = ['ERROR: NSB_EDFreader >> ',ME.message];
        if ~isempty(options.logfile)
            status = DMD_logger(options.logfile,errorstr);
        else
            msg = errorstr;
        end
        fclose(fid);
        return;
    
end
status = true;

function flag = doScaling(label)
    %Defaults to true = do sclaing
    flag = true;
    switch lower(label)
        case 'categor'
            flag = false;
        case ''
            flag = false;
    end


