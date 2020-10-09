function [status, errorstr] = DMD_EDFplusWriter(DataStruct, filename, options)
%
% Inputs:
%   DataStruct              - (struct) from DevilbissLab DataStructure (derived from Neuroexplorer Data structure)
%   filename                - (string) filename to save to
%   options                 - (struct) of options
%                               .logfile
%                               .chans
%                               .progress
% Outputs:
%   status               - (logical) return value
%   errorstr             - (string) description of error
%
% Data struct assumed to have an 'EDF Annotations' channel. If so this is an EDF+ and this function will add an additional channel of the text annotations.

%% Handle In-outputs
status = false;errorstr = '';
if nargin < 3
    options.logfile = '';
    options.chans = [];
    options.progress = true;
end

%Create folder if non exists
[fnPath,fn,fnExt] = fileparts(filename);
if exist(fnPath,'dir') ~= 7
    mkdir(fnPath);
end


%% Precalculate items for header
% Find Annotatons channel (returns IDX or [])
ChNames = {DataStruct.Channel.Name};
TalChanIDX = find(strcmpi(ChNames,'EDF Annotations'));
if length(TalChanIDX) > 1
    errorstr = 'ERROR: DMD_EDFplusWriter >> DataStruct can only have one "EDF Annotations" Channel';
    if ~isempty(options.logfile)
        status = DMDlogger(options.logfile,errorstr);
    else
        errordlg(errorstr,'DMD_EDFplusWriter');
    end
end

% Determine whether TalChannel has text labels associated with it.
TalChan = false;
TalChanTS = false;
if ~isempty(TalChanIDX)
if isfield(DataStruct.Channel,'Labels')
    if ~isempty(DataStruct.Channel(TalChanIDX).Labels)
    TalChan = true;
    end
end
if isfield(DataStruct.Channel,'ts')
    if ~isempty(DataStruct.Channel(TalChanIDX).ts)
    TalChanTS = true;
    end
end
end

% Determine how Many Channels To write
nChannels = DataStruct.nChannels;
if TalChan
    nChannels = nChannels +1; %TAL channel 'EDF Annotations'
end

% Calculate File Size
% Make sure DataStruct.nSeconds is correct
maxHz = max([DataStruct.Channel.Hz]);
temp = find([DataStruct.Channel.Hz] == maxHz );
for curChan = temp
    chanSecs(curChan) = length(DataStruct.Channel(curChan).Data) / maxHz;
end
TotalDuration = max(max(chanSecs),DataStruct.nSeconds);
DataStruct.nSeconds = TotalDuration;

% Determine Data record Size and number of samples the largest Tal will
% takeup
[RecSize,maxTalSize] = getRecordDuration(DataStruct);

% Calculate Number of records
% Remenber, Last record could be unfilled !!!
nRecords = ceil(TotalDuration/RecSize);




%% Prepare EDF Header
%In the header, use only printable US-ASCII characters with byte values 32..126.
HDRstring = '';

%%% Version (this is '0      ' for EDF and EDF+)
element = char(num2str(0), sprintf('%8s',' '));
element = element(1,:);
HDRstring = [HDRstring, element];

%%% 'local patient identification'
% - the code by which the patient is known in the hospital administration.
% - sex (English, so F or M).
% - birthdate in dd-MMM-yyyy format using the English 3-character abbreviations of the month in capitals. 02-AUG-1951 is OK, while 2-AUG-1951 is not.
% - the patients name.
%patient code
if isfield(DataStruct,'SubjectID')
    %make sure there are no spaces in the ID
    element = regexprep(DataStruct.SubjectID,'[\.\s]','-');
else
    % use hospital administration Code
    if isfield(DataStruct,'AdminUID')
        element = regexprep(DataStruct.UID,'\s','-');
    else
        element = 'X';
    end
end
%Gender
if isfield(DataStruct,'Gender')
    el = upper(DataStruct.Gender(1));
    if ~ismember({'M','F'},el)
        el = 'X';
    end
    element = DMD_strcat(element,' ',el); %only take 1st letter
else
    element = DMD_strcat(element,' X');
end
%birthdate in dd-MMM-yyyy
try
    if isfield(DataStruct,'BirthDate')
        element = DMD_strcat(element,' ',upper(datestr(DataStruct.BirthDate,'dd-mmm-yyyy')));
    elseif isfield(DataStruct,'Birthdate')
        element = DMD_strcat(element,' ',upper(datestr(DataStruct.Birthdate,'dd-mmm-yyyy')));
    else
        element = DMD_strcat(element,' X');
    end
catch
    element = DMD_strcat(element,' X');
end
%patients name
if isfield(DataStruct,'SubjectName')
    element = DMD_strcat(element,' ',regexprep(DataStruct.SubjectID,'\s','-'));
else
    element = DMD_strcat(element,' X');
end
%Additional subfields may follow the ones described here.
element(80:end) = []; %truncate to 80 char
element = char(element, sprintf('%80s',' '));
element = element(1,:); %Pad to 80 char with spaces
HDRstring = [HDRstring, element];

%'local recording identification'
% - The text 'Startdate'.
% - The startdate itself in dd-MMM-yyyy format using the English 3-character abbreviations of the month in capitals.
% - The hospital administration code of the investigation, i.e. EEG number or PSG number.
% - A code specifying the responsible investigator or technician.
% - A code specifying the used equipment.
%
%Startdate text
element = 'Startdate';
% Startdate
if isfield(DataStruct,'StartDate')
    element = DMD_strcat(element,' ',upper(datestr(DataStruct.StartDate,'dd-mmm-yyyy')));
else
    element = DMD_strcat(element,' X');
end
% hospital administration code Investigation
if isfield(DataStruct,'AdminUID')
    element = DMD_strcat(element,' ',DataStruct.AdminUID);
else
    element = DMD_strcat(element,' X');
end
%responsible investigator or technician
if isfield(DataStruct,'Technician')
    element = DMD_strcat(element,' ',DataStruct.Technician);
else
    element = DMD_strcat(element,' X');
end
%equipment used
if isfield(DataStruct,'Equipment')
    element = DMD_strcat(element,' ',DataStruct.Equipment);
else
    element = DMD_strcat(element,' X');
end
%Additional subfields may follow the ones described here.
%append NSB data
element = DMD_strcat(element,' DMDwritten',datestr(now,30)); 
element(80:end) = []; %truncate to 80 char
element = char(element, sprintf('%80s',' ')); element = element(1,:); %Pad to 80 char with spaces
HDRstring = [HDRstring, element];
%Stored Comment
if isfield(DataStruct,'Comment')
    element = DMD_strcat(element,' ',regexprep(strtrim(DataStruct.Comment),'[\.\s]','-'));
else
    element = DMD_strcat(element,' X');
end

%%% startdate (dd.mm.yy)
% use 1985 as a clipping date in order to avoid the Y2K problem. So, the years 1985-1999 must be represented by yy=85-99 and the years 2000-2084 by yy=00-84. After 2084, yy must be 'yy' and only item 4 of this paragraph defines the date.
element = datestr(DataStruct.StartDate, 'dd.mm.yy');
HDRstring = [HDRstring, element];

%%% starttime (hh.mm.ss)
element = datestr(DataStruct.StartDate, 'HH.MM.SS');
HDRstring = [HDRstring, element];

%%% number of bytes in header record
element = char(num2str(256 + 256*nChannels), sprintf('%8s',' '));
element = element(1,:);
HDRstring = [HDRstring, element];

%%% 44 ascii : reserved
% the first 'reserved' field (44 characters) which must start with 'EDF+C' if the recording is uninterrupted, thus having contiguous data records, i.e. the starttime of each data record coincides with the end (starttime + duration) of the preceding one. In this case, the file is EDF compatible and the recording ends (number x duration) seconds after its startdate/time. The 'reserved' field must start with 'EDF+D' if the recording is interrupted, so not all data records are contiguous. In both cases, the time must be kept in each data record as specified in section 2.2.4.
% To date only EDF+C is supprorted
% If writing a vanilla EDF this shouldn't matter
element = 'EDF+C';
element = char(element, sprintf('%44s',' ')); element = element(1,:); %Pad to 80 char with spaces
HDRstring = [HDRstring, element];

%%% number of Data Records
element = char(num2str(nRecords), sprintf('%8s',' ')); element = element(1,:);
HDRstring = [HDRstring, element];

%%% Duration of Data RECORD
element = char(num2str(RecSize), sprintf('%8s',' ')); element = element(1,:);
HDRstring = [HDRstring, element];

%%% Num Channels
element = char(num2str(nChannels), sprintf('%4s',' ')); element = element(1,:);
HDRstring = [HDRstring, element];
% OK = 256

%% Prepare EDF Channel Headers
% Labels in EDF+ contain 'XXX name' where XXX is a LabelType and name is the
% name of the channel
LabelTypes = {'EEG','ECG','EOG','ERG','EMG','MEG','MCG','EP'};

ChanHDRstring = '';
%%% Label
% the standard label reads 'EEG Fpz-Cz      '. Further possibilities are listed in the signals table below.
% http://www.edfplus.info/specs/edftexts.html#signals
for curChan = 1:DataStruct.nChannels
    element = DataStruct.Channel(curChan).Name;
    if isfield(DataStruct.Channel(curChan),'ChNumber')
        element = fixLabel(element,DataStruct.Channel(curChan).ChNumber,LabelTypes);
    else
        element = fixLabel(element,curChan,LabelTypes);
    end
    element(16:end) = []; %truncate to 16 char
    element = char(element, sprintf('%16s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    element = 'EDF Annotations';
    element = char(element, sprintf('%16s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end

%%% Transducer
for curChan = 1:DataStruct.nChannels
    if isfield(DataStruct.Channel(curChan),'Transducer')
        element = DataStruct.Channel(curChan).Transducer;
    else
        element = '';
    end
    element(81:end) = []; %truncate to 80 char
    element = char(element, sprintf('%80s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    element = '';
    element = char(element, sprintf('%80s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end

%%% Physical Dimension (string)
for curChan = 1:DataStruct.nChannels
    element = DataStruct.Channel(curChan).Units; element(8:end) = []; %truncate to 8 char
    element = char(element, sprintf('%8s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    element = '';
    element = char(element, sprintf('%8s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end

%%% Physical min
for curChan = 1:DataStruct.nChannels
    PhysicalMin(curChan) = min(DataStruct.Channel(curChan).Data);
    if isempty(PhysicalMin(curChan))
        PhysicalMin(curChan) = 0;
    end
    element = char(num2str(PhysicalMin(curChan)), sprintf('%8s',' ')); element = element(1,1:8); %force truncation here since MatLAb doesnt thingk (-) is a character
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    element = num2str(0);
    element = char(element, sprintf('%8s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end

%%% Physical Max
for curChan = 1:DataStruct.nChannels
    PhysicalMax(curChan) = max(DataStruct.Channel(curChan).Data);
    if isempty(PhysicalMax(curChan))
        PhysicalMax(curChan) = 0;
    end
    if PhysicalMax(curChan) == PhysicalMin(curChan)
        PhysicalMax(curChan) = PhysicalMin(curChan) +1;
    end
    element = char(num2str(PhysicalMax(curChan)), sprintf('%8s',' ')); element = element(1,1:8); %force truncation here since MatLAb doesnt thingk (-) is a character
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    %TAL -The 'Physical maximum' and 'Physical minimum' fields must contain values that differ from each other
    element = num2str(1);
    element = char(element, sprintf('%8s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end

%%% Dig Min int 16 = -32768
for curChan = 1:DataStruct.nChannels
    element = char(num2str(-32768), sprintf('%8s',' ')); element = element(1,1:8); %force truncation here since MatLab doesnt think (-) is a character
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    element = char(num2str(-32768), sprintf('%8s',' '));
    element = element(1,1:8); %force truncation here since MatLab doesnt think (-) is a character
    ChanHDRstring = [ChanHDRstring, element];
end

%%% Dig Max int 16 = 32767
for curChan = 1:DataStruct.nChannels
    element = char(num2str(32767), sprintf('%8s',' ')); element = element(1,1:8); %force truncation here sinceMatLab doesnt think (-) is a character
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    element = char(num2str(32767), sprintf('%8s',' '));
    element = element(1,1:8); %force truncation here since MatLab doesnt think (-) is a character
    ChanHDRstring = [ChanHDRstring, element];
end

%%% Prefiltering
for curChan = 1:DataStruct.nChannels
    if isfield(DataStruct.Channel(curChan),'PreFilter')
        element = DataStruct.Channel(curChan).PreFilter;
    elseif isfield(DataStruct.Channel(curChan),'Transducer')
        element = DataStruct.Channel(curChan).Transducer;
    else
        element = '';
    end
    element(81:end) = []; %truncate to 80 char
    element = char(element, sprintf('%80s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    element = '';
    element = char(element, sprintf('%80s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end

%%% Samples per Data Record - Save in vector for later.....        <<<<<<<<  Check this for low Hz
for curChan = 1:DataStruct.nChannels
    recordSamples(curChan) = DataStruct.Channel(curChan).Hz*RecSize;
    element = char(num2str(recordSamples(curChan)), sprintf('%8s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    curChan = curChan +1;
    recordSamples(curChan) = maxTalSize;                     %<<<<<<<<  Check this This needs to include the "sample rate" of TALs
    element = char(num2str(recordSamples(curChan)), sprintf('%8s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end

%reserved
for curChan = 1:DataStruct.nChannels
    element = char(sprintf('%32s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end
if TalChan
    element = char(sprintf('%32s',' ')); element = element(1,:);
    ChanHDRstring = [ChanHDRstring, element];
end

%OK 256 + (nSignals * 256)


%% Write EDF Channel Headers
% open file
try
    fid = fopen(filename,'w+','ieee-le','US-ASCII'); %use W for no flush & faster write
    if fid < 0
        DataStruct = [];
        errorstr = ['ERROR: DMD_EDFplusWriter >> Cannot open: ',filename];
        if ~isempty(options.logfile)
            status = DMDlogger(options.logfile,errorstr);
        else
            errordlg(errorstr,'DMD_EDFplusWriter');
        end
        fclose(fid);
        return;
    end
    nElements = fwrite(fid, HDRstring, 'char');
    if nElements ~= 256
        errorstr = 'ERROR: DMD_EDFplusWriter >> EDF Header is not 256 bytes';
        if ~isempty(options.logfile)
            status = DMDlogger(options.logfile,errorstr);
        else
            errordlg(errorstr,'DMD_EDFplusWriter');
        end
    end
    nElements = fwrite(fid, ChanHDRstring, 'char');
    if nElements ~= 256*nChannels
        errorstr = ['ERROR: DMD_EDFplusWriter >> EDF Channel Header is not ',num2str(256*nChannels),' bytes'];
        if ~isempty(options.logfile)
            status = DMDlogger(options.logfile,errorstr);
        else
            errordlg(errorstr,'DMD_EDFplusWriter');
        end
    end
    
    %% Write EDF Data
    % note: watch out for incomplete final frame
    if options.progress, h = waitbar(0,'Saving Record 0 ...'); end
    
    recSampleStart = ones(nChannels,1);
    recSampleEnd = recordSamples(:);
    LabelCounter = 1;
    %debug only
    %WrittenData = ftell(fid);
    %disp(['Header dataWritten: ',num2str(WrittenData)]);
    
    %loop through each record
    for curRecord = 1:nRecords
        if options.progress, waitbar(curRecord/nRecords,h,['Saving Record ',num2str(curRecord),' ...']); end
        
        %loop through each channel (but not Annotations channel)
        for curChan = 1:nChannels-1
            if recSampleEnd(curChan) <= length(DataStruct.Channel(curChan).Data)
                writeData = DataStruct.Channel(curChan).Data(recSampleStart(curChan):recSampleEnd(curChan));
            else
                writeData = DataStruct.Channel(curChan).Data(recSampleStart(curChan):end);
                buffer = zeros(recordSamples(curChan) - length(writeData),1);
                writeData = [writeData; buffer];
            end
            %Handle beg/end of segment differently for each channel since they are likely different
            %writeData = DataStruct.Channel(curChan).Data(recSampleStart(curChan):recSampleEnd(curChan));
            %scale data as interger
            %writeData =  writeData / (PhysicalMax(curChan) - PhysicalMin(curChan)) / (32767 - -32768);
            if isempty(strfind(DataStruct.Channel(curChan).Units,'Categ'))
                writeData =  writeData / ((PhysicalMax(curChan) - PhysicalMin(curChan)) / (32767 - -32768));
            end
            nElements = fwrite(fid, writeData, 'int16');
            %debug only
            %WrittenData = WrittenData + nElements*2;
            %disp(['nElements >> Record#',num2str(curRecord),' Channel#',num2str(curChan),' = ',num2str(nElements)]);
            %voltage (i.e. signal) in the file by definition equals [(physical miniumum) + (digital value in the data record - digital minimum) x (physical maximum - physical minimum) / (digital maximum - digital minimum)].
            %update file positions
            recSampleStart(curChan) = recSampleStart(curChan) + recordSamples(curChan);
            recSampleEnd(curChan) = recSampleEnd(curChan) + recordSamples(curChan);
        end
        
        % now write TALs
        % This currenlty has no ability to write in timestamps from data
        if TalChan
            % maxTalSize number of data samples the tal MUST include
            TalBytes = maxTalSize *2;
            TALString = ['+',num2str( (curRecord -1) * RecSize),char(20),char(20),char(0)]; %timekeeping TAL
            try
                for curTAL = 1:(RecSize * DataStruct.Channel(TalChanIDX).Hz)
                    if TalChanTS
                        
                    else
                    TALString = [TALString, '+',num2str( (curRecord -1) * RecSize + (curTAL -1) * 1/DataStruct.Channel(TalChanIDX).Hz ), char(21), ...
                        num2str(1/DataStruct.Channel(TalChanIDX).Hz), char(20),...
                        DataStruct.Channel(TalChanIDX).Labels{LabelCounter}, char(20), char(0)];
                    
                    end
                    LabelCounter = LabelCounter +1;
                end
            catch ME
                errorstr = ['ERROR: NSB_EDFreader >> Missing TAL Data for Record:',num2str(curRecord)];
                if ~isempty(options.logfile)
                    status = DMDlogger(options.logfile,errorstr);
                else
                    errordlg(errorstr,'NSB_EDFreader');
                end
                errorstr = ['ERROR: NSB_EDFreader >> ',ME.message];
                if ~isempty(options.logfile)
                    status = DMDlogger(options.logfile,errorstr);
                else
                    errordlg(errorstr,'NSB_EDFreader');
                end
            end
            
            TALString = [TALString, char(zeros(1,TalBytes - length(TALString)))];
            nElements = fwrite(fid, TALString, 'char');
            
            if nElements ~= TalBytes
                errorstr = ['ERROR: DMD_EDFplusWriter >> TAL length is not ',num2str(TalBytes),' bytes'];
                if ~isempty(options.logfile)
                    status = DMDlogger(options.logfile,errorstr);
                else
                    errordlg(errorstr,'DMD_EDFplusWriter');
                end
            end
            
            %debug only.
            %WrittenData = WrittenData + nElements;
            %disp(['dataWritten: ',num2str(WrittenData)]);
            %disp(['nElements >> Record#',num2str(curRecord),' TAL = ',num2str(nElements)]);
            
        end
    end
    
    try, close(h), end;
    
    %% Error Catching
catch ME
    errorstr = ['ERROR: NSB_EDFreader >> ',ME.message];
    if ~isempty(options.logfile)
        status = DMDlogger(options.logfile,errorstr);
    else
        errordlg(errorstr,'NSB_EDFreader');
    end
    fclose(fid);
    return;
    
end
fclose(fid);
status = true;

function [RecSize,maxTalSize] = getRecordDuration(DataStruct)
%duration of a data record, in seconds
%In EDF(+), data record Durations are specified in an 8-character string, for instance 0.123456 or 1234567
%In one datarecord, maximum 61440 bytes are available for all signals (including the Annotation signal).
% encoded as int16 so 61440/2 values avalvble.
RecSize = [];maxTalSize=[];
AvalBytes = 61440;
AvalSamples = AvalBytes / 2; %aval samples in data record

% This is flawed because it returns the duration of the TAL max length AND
% time keeper TAL. 
% It also does not take into account how many TALs need to be in a
% datarecord and if they will fit!
[maxTalSize,status] = getTalDuration(DataStruct);
if ~status
    %no TALs or function failed
    fpringf(2,'Warning>>DMD_EDFplusWriter:getRecordDuration could not determine TAL size');
    maxTalSize = 0;
end

AvalSamples = AvalSamples - maxTalSize; %aval samples in data record after TALs are added in
%calculate the best precision versus record size and find optimum record size
MaxDuration = str2double(sprintf('%8f',AvalSamples/ sum(ceil([DataStruct.Channel(:).Hz]))));
SampDurs = 0.000001:0.000001:MaxDuration;
relativeError = mod(SampDurs * min([DataStruct.Channel(:).Hz]),1)/ min([DataStruct.Channel(:).Hz]);
RecSize = floor(SampDurs(find(relativeError == min(relativeError),1,'last'))); %duration in seconds as floor to deal with eps issue

function [maxTalSize,status] = getTalDuration(DataStruct)
%Time-stamped Annotations Lists (TALs) in an 'EDF Annotations' signal
%Text, time-keeping, events and stimuli are coded as text annotations in this 'EDF Annotations' signal.
%calculate data sample length needed to encode all TALs in a data record
% All times in a TAL are in seconds
% the minimum tal length is length(['+xxx',char(20),char(20),char(0)]) with xxx being the timestamp length
%eg +,0,char(20),char(20),char(0) - ts (TimeKeeping) TAL
%eg +,0,char(21),duration,char(20),description,char(20),char(0) - sleepscoring interval TAL
%
% function returns the max number of samples the longest TAL will need
%NOTE: 'samples in data record' are ceil(maxTalSize/2)*2
%
status = false; maxTalSize = [];
ChNames = {DataStruct.Channel.Name};
TalChan = strcmpi(ChNames,'EDF Annotations');
if any(TalChan)
    maxNumlength = length(num2str(DataStruct.nSeconds)) + length(num2str(1/ max([DataStruct.Channel.Hz])));
    maxTimeKeeperTAL = 4 + maxNumlength;
    try
        maxDiscLength = max(cellfun(@length,DataStruct.Channel(TalChan).Labels));
        % maxTalSize: we are adding 2 maxTS lengths because we do not know if
        % the TALs that we are creating have a duration and the longest
        % duration is the length of the file. Additionally we add (5) length for sign and terminator(s)
        maxTalSize = maxTimeKeeperTAL + maxNumlength + maxNumlength + maxDiscLength + 5;
    catch
        maxTalSize = maxTimeKeeperTAL;
    end
else
    %cannot find TALs
    return;
end
maxTalSize = ceil(maxTalSize/2);
maxTalSize = ceil(maxTalSize/10) * 10; %reserve up to the next 10 samples
status = true;

function out = fixLabel(Label,ChNum,LabelTypes)
% Labels in EDF+ contain 'XXX name' wher XXX is a LabelType and name is the
% name of the channel
%LabelTypes = {'EEG','ECG','EOG','ERG','EMG','MEG','MCG','EP'};
out = '';

if any(~cellfun(@isempty,strfind(LabelTypes,upper(Label(1:3))))) %has a correct lable type as 1st 3 letters
    if length(Label) > 3
        out = [upper(Label(1:3)),' ',regexprep(strtrim(Label(4:end)),'\s','_')];
    else
        out = [upper(Label(1:3)),' Channel-',num2str(ChNum)];
    end
else
    out = regexprep(strtrim(Label),'\s','_');
end

function t = DMD_strcat(varargin)
%DMD_STRCAT Concatenate strings.
%   Rewrite of STRCAT to have better and specific properties.
%
%   COMBINEDSTR = DMD_strcat(S1, S2, ..., SN) horizontally concatenates strings
%   in arrays S1, S2, ..., SN. Inputs can be combinations of single
%   strings, strings in scalar cells, character arrays with the same number
%   of rows, and same-sized cell arrays of strings.
%
%   Notes:
%
%   Allows empty inputs. collapses multiple white space into a single
%   whitespace character. Trims lead and lag insignifigant characters.
%
%   Example:
%
%       strcat('Red',' ','Yellow',{'Green';'Blue'})
%
%   returns
%
%       'Red YellowGreenBlue'
%
%   See also CAT, CELLSTR.


narginchk(1, inf);

% initialise return arguments
t = '';

% return empty string when all inputs are empty
rows = cellfun('size',varargin,1);
if all(rows == 0)
    return;
end

%limit inputs to two dimensions
dims = (cellfun('ndims',varargin) == 2);
if ~all(dims)
    error(message('NSB:NSB_strfun:InputDimension'));
end


if all(rows == 1) && ~any(cellfun(@iscell,varargin))
    %if all varargin are one row and no cells.
    t = [varargin{:}];
else
    for n = 1:length(varargin)
        if ~iscell(varargin{n})
            t = [t, varargin{n}];
        elseif iscell(varargin{n})
            % Expand if cell is more than one row.
            str = '';
            for m = 1:rows(n)
                str = [str, varargin{n}{m}];
            end
            t = [t, str];
        else
            error(message('NSB:NSB_strfun:InputType'));
        end
    end
end

%Replace >1 white space with single space
t = strtrim(regexprep(t,'\s{2,}',' '));

function status = DMDlogger(LogFileName,LogStr)

try
    fid = fopen(LogFileName,'at');
    if iscellstr(LogStr)
        for i=1:length(LogStr)
            fprintf(fid, '%s\n',LogStr{i});
        end
    else
        fprintf(fid, '%s\n',LogStr);
    end
    fclose(fid);
    status = true;
catch
    status = false;
end