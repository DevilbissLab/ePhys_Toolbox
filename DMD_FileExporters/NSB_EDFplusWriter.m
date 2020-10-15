function [status, errorstr] = NSB_EDFplusWriter(DataStruct, filename, options)
%[status] = NSB_EDFplusWriter(DataStruct, filename, options)
%
% Inputs:
%   DataStruct              - (struct) from PreclinicalEEGFramework
%   filename                - (string) filename to save to
%   options                 - (struct) of options 
%                               .logfile
%                               .chans
%                               .progress
% Outputs:
%   status               - (logical) return value
%
% Written By David M. Devilbiss
% NexStep Biomarkers, LLC. (info@nexstepbiomarkers.com)
% June 2013, Version 1.0
% July 2013, Version 1.1 Fixed issue with strcat and issue of miscalculated
% file size

%Assumes new field DataStruct.SleepScore (not in individual channels)
%Check Truncations Char length +1
%Check indexing on file write so you are not resamppling the last point... 
%swap NSB_strcat with []because NSB_strcat r?emoves white space

% Labels in EDF+ contain 'XXX name' wher XXX is a LabelType and name is the
% name of the channel
LabelTypes = {'EEG','ECG','EOG','ERG','EMG','MEG','MCG','EP'};

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

% Determine whether file is EDF or EDF+
if all(ismember({DataStruct.Channel.Name},LabelTypes))
    status = NSB_EDFwriter(DataStruct, filename, options);
    return;
end

%Collect information about file
% how Many Channels To write
nChannels = DataStruct.nChannels;
nChannels = nChannels +1; %TAL channel 'EDF Annotations'

%calculate Data record Durations
%In EDF(+), data record Durations are specified in an 8-character string, for instance 0.123456 or 1234567
%In one datarecord, maximum 61440 bytes are available for all signals (including the Annotation signal).
% encoded as int16 so 61440/2 values avalvble.
AvalBytes = 61440 / 2; % you will subtract anotation size here <<
MaxDuration = str2double(sprintf('%8f',AvalBytes/ sum(ceil([DataStruct.Channel(:).Hz]))));
SampDurs = 0.000001:0.000001:MaxDuration;
relativeError = mod(SampDurs * min([DataStruct.Channel(:).Hz]),1)/ min([DataStruct.Channel(:).Hz]);
RecSize = single(SampDurs(find(relativeError == min(relativeError),1,'last'))); %duration in seconds as single to deal with eps issue

%Now determine wheather your TAL can fit in remainder bytes
%calculate TAL length
%the minimum tal length is length(['+xxx',char(20),char(20),char(0)]) with xxx being the timestamp length
%eg +,0,char(20),char(20),char(0) - ts TAL
%eg +,0,char(21),duration,char(20),description,char(20),char(0) - sleepscoring interval TAL
%
maxTalLength = 0;
HypTalLength = 0;
HypMaxDur = 0;
for curChan = 1:DataStruct.nChannels
    if isfield(DataStruct.Channel(curChan),'ts')
    if ~isempty(DataStruct.Channel(curChan).ts) %EDF's do not have time stamps
        maxTalLength = max(maxTalLength,length(num2str(DataStruct.Channel(curChan).ts(end))));
    end
    else
        maxTalLength =  max(maxTalLength, length(num2str( length(DataStruct.Channel(curChan).Data)/DataStruct.Channel(curChan).Hz )));
    end
end
if maxTalLength ~= 0
    maxTalLength = maxTalLength + 4; %add length for sign and terminator(s) ''
end
ReserveTalBytes = maxTalLength;

%get Hypnogram channel (for TALs)
HypnogramChan = [];
if isempty(HypnogramChan) && ~isempty(find(strcmpi('EDF Annotations',{DataStruct.Channel(:).Name})))
    if isfield(DataStruct.Channel(:),'Labels')
        HypnogramChan = find(strcmpi('EDF Annotations',{DataStruct.Channel(:).Name}));
        for curChan = 1:length(HypnogramChan)
            if ~isempty(DataStruct.Channel(HypnogramChan(curChan)).Labels)
                HypnogramChan = HypnogramChan(curChan);
                break;
            else
                HypnogramChan = [];
            end
        end
    end
end
if isempty(HypnogramChan) && ~isempty(find(strcmpi('Hypnogram',{DataStruct.Channel(:).Name})))
    if isfield(DataStruct.Channel(:),'Labels')
        HypnogramChan = find(strcmpi('Hypnogram',{DataStruct.Channel(:).Name}));
        for curChan = 1:length(HypnogramChan)
            if ~isempty(DataStruct.Channel(HypnogramChan(curChan)).Labels)
                HypnogramChan = HypnogramChan(curChan);
                break;
            else
                HypnogramChan = [];
            end
        end
    end
end
if isempty(HypnogramChan) && ~isempty(find(strcmpi('Marker',{DataStruct.Channel(:).Name})))
    if isfield(DataStruct.Channel(:),'Labels')
        HypnogramChan = find(strcmpi('Marker',{DataStruct.Channel(:).Name}));
        for curChan = 1:length(HypnogramChan)
            if ~isempty(DataStruct.Channel(HypnogramChan(curChan)).Labels)
                HypnogramChan = HypnogramChan(curChan);
                break;
            else
                HypnogramChan = [];
            end
        end
    end
end            
      
% HypnogramChan = [find(strcmpi('Hypnogram',{DataStruct.Channel(:).Name})), ...
%     find(strcmpi('Marker',{DataStruct.Channel(:).Name})),...
%     find(strcmpi('EDF Annotations',{DataStruct.Channel(:).Name}))];

if ~isempty(HypnogramChan)
    for curChan = HypnogramChan
        if ~isempty(DataStruct.Channel(curChan).Labels)
       HypTalLength = max( HypTalLength,  max(cellfun(@length,unique(DataStruct.Channel(curChan).Labels))) );
       HypMaxDur = max( HypMaxDur, 1/DataStruct.Channel(curChan).Hz); %in seconds
        end
    end
    %Here we are only calculating to include a single sleepscoring channel 
    HypTalLength = HypTalLength + length(num2str(HypMaxDur)) + maxTalLength + 1; %additional 1 is to add char(21)
    
    ReserveTalBytes = maxTalLength + HypTalLength * ceil(RecSize / HypMaxDur);
    ReserveTalBytes = ceil(ReserveTalBytes/2) * 2;%always reserve an even number of bytes
    HypnogramChan = HypnogramChan(1); %<<< Hardcoded to only report 1st Hypnogram in tal
else
    
    %this is an edf file so write as one
    status = NSB_EDFwriter(DataStruct, filename, options);
    return;
end

RemBytes = AvalBytes - sum([DataStruct.Channel(:).Hz]) * RecSize;
if ReserveTalBytes > RemBytes
    %throuw err < here you would need to recalculate...
    error('ReserveTalBytes > RemBytes');
    return;
end

%Now that you are done calculating / recalculating you can write the file.
nRecords = ceil(DataStruct.nSeconds/RecSize); %Last record could be unfilled !!!
%check this for validity because some data (DSI) does not report this
%accurately?
for curChan = 1:DataStruct.nChannels
    nRecord(curChan) = length(DataStruct.Channel(curChan).Data) / DataStruct.Channel(curChan).Hz /RecSize;
end
if nRecords ~= max(nRecord)
    errorstr = 'Warning: NSB_EDFreader >> Reported file duration does not equal samples recorded. Using file data to determine duration.';
    if ~isempty(options.logfile)
        status = NSBlog(options.logfile,errorstr);
    else
        errordlg(errorstr,'NSB_EDFreader');
    end
    nRecords = max(nRecord);
end
nSamples = floor(RecSize * max(sum([DataStruct.Channel(:).Hz]))); %<<chk Cur not used
clear SampDurs relativeError;

% open file
try
fid = fopen(filename,'w+','ieee-le','US-ASCII'); %use W for no flush & faster write
    if fid < 0
        DataStruct = [];
        errorstr = ['ERROR: NSB_EDFreader >> Cannot open: ',filename];
        if ~isempty(options.logfile)
            status = NSBlog(options.logfile,errorstr);
        else
            errordlg(errorstr,'NSB_EDFreader');
        end
        fclose(fid);
        return;
    end
    
%% Write EDF Header
%In the header, use only printable US-ASCII characters with byte values 32..126. 
%Version (this is '0      ' for EDF and EDF+)
element = char(num2str(0), sprintf('%8s',' ')); element = element(1,:);
nElements = fwrite(fid, element, 'char');

%'local patient identification'
if ~isempty(strfind(DataStruct.FileFormat,'.edf'))
    %original file was EDF(+) - But may not have been written correctly.
    %element = DataStruct.SubjectID;
    element = regexprep(DataStruct.SubjectID,'[\.\s]','-');
else
    % hospital administration Code
    if isfield(DataStruct,'UID')
        element = regexprep(DataStruct.UID,'\s','-');
    else
        element = 'X';
    end
end
    %Gender
    if isfield(DataStruct,'Gender')
        element = NSB_strcat(element,' ',upper(DataStruct.Gender(1))); %only take 1st letter
    else
        element = NSB_strcat(element,' X');
    end
    %birthdate in dd-MMM-yyyy
    if isfield(DataStruct,'Birthdate')
        element = NSB_strcat(element,' ',upper(datestr(DataStruct.Birthdate,'dd-mmm-yyyy')));
    else
        element = NSB_strcat(element,' X');
    end
    %patients name
    if isfield(DataStruct,'SubjectID')
        element = NSB_strcat(element,' ',regexprep(DataStruct.SubjectID,'\s','-')); %only take 1st letter
    else
        element = NSB_strcat(element,' X');
    end
    %Additional subfields may follow the ones described here. 
element(80:end) = []; %truncate to 80 char
element = char(element, sprintf('%80s',' ')); 
element = element(1,:); %Pad to 80 char with spaces
nElements = fwrite(fid, element, 'char'); %write element

%'local recording identification'
% - The text 'Startdate'. 
% - The startdate itself in dd-MMM-yyyy format using the English 3-character abbreviations of the month in capitals. 
% - The hospital administration code of the investigation, i.e. EEG number or PSG number. 
% - A code specifying the responsible investigator or technician. 
% - A code specifying the used equipment.
if ~isempty(strfind(DataStruct.FileFormat,'.edf'))
    %original file was EDF(+)
    %element = DataStruct.Comment;
    if strcmpi(DataStruct.Comment(1:9),'Startdate')
    element = regexprep(DataStruct.Comment,'[\.\s]','-');
    else
    element = 'Startdate';
    if isfield(DataStruct,'StartDate')
        element = NSB_strcat(element,' ',upper(datestr(DataStruct.StartDate,'dd-mmm-yyyy')));
    else
        element = NSB_strcat(element,' X');
    end
    % hospital administration code Investigation
    if isfield(DataStruct,'Study')
        element = NSB_strcat(element,' ',DataStruct.Study);
    else
        element = NSB_strcat(element,' X');
    end

    %responsible investigator or technician
    if isfield(DataStruct,'Technician')
        element = NSB_strcat(element,' ',DataStruct.Technician);
    else
        element = NSB_strcat(element,' X');
    end
        %used equipment
    if isfield(DataStruct,'Comment')
        element = NSB_strcat(element,' ',regexprep(strtrim(DataStruct.Comment),'[\.\s]','-'));
    else
        element = NSB_strcat(element,' X');
    end
    %Additional subfields may follow the ones described here. 
    if isfield(DataStruct,'VersionName') %DSI version if Specified
        element = NSB_strcat(element,' ',DataStruct.VersionName);
    else
        element = NSB_strcat(element,' X');
    end
    end
else
    %Startdate
    element = 'Startdate';
    if isfield(DataStruct,'StartDate')
        element = NSB_strcat(element,' ',upper(datestr(DataStruct.StartDate,'dd-mmm-yyyy')));
    else
        element = NSB_strcat(element,' X');
    end
    % hospital administration code Investigation
    if isfield(DataStruct,'Study')
        element = NSB_strcat(element,' ',DataStruct.Study);
    else
        element = NSB_strcat(element,' X');
    end

    %responsible investigator or technician
    if isfield(DataStruct,'Technician')
        element = NSB_strcat(element,' ',DataStruct.Technician);
    else
        element = NSB_strcat(element,' X');
    end
    %used equipment
    if isfield(DataStruct,'HardwareID')
        element = NSB_strcat(element,' ',DataStruct.HardwareID);
    else
        element = NSB_strcat(element,' X');
    end
    %Additional subfields may follow the ones described here. 
    if isfield(DataStruct,'VersionName') %DSI version if Specified
        element = NSB_strcat(element,' ',DataStruct.VersionName);
    else
        element = NSB_strcat(element,' X');
    end
end
element = NSB_strcat(element,' NSBwritten',datestr(now,30)); %append NSB data
element(80:end) = []; %truncate to 80 char
element = char(element, sprintf('%80s',' ')); element = element(1,:); %Pad to 80 char with spaces
nElements = fwrite(fid, element, 'char'); %write element

%startdate (dd.mm.yy)
% use 1985 as a clipping date in order to avoid the Y2K problem. So, the years 1985-1999 must be represented by yy=85-99 and the years 2000-2084 by yy=00-84. After 2084, yy must be 'yy' and only item 4 of this paragraph defines the date. 
nElements = fwrite(fid, datestr(DataStruct.StartDate, 'dd.mm.yy'), 'char'); 
%starttime (hh.mm.ss) 
nElements = fwrite(fid, datestr(DataStruct.StartDate, 'HH.MM.SS'), 'char'); 
%number of bytes in header record
element = char(num2str(256 + 256*nChannels), sprintf('%8s',' ')); element = element(1,:);
nElements = fwrite(fid, element, 'char');

%44 ascii : reserved
% the first 'reserved' field (44 characters) which must start with 'EDF+C' if the recording is uninterrupted, thus having contiguous data records, i.e. the starttime of each data record coincides with the end (starttime + duration) of the preceding one. In this case, the file is EDF compatible and the recording ends (number x duration) seconds after its startdate/time. The 'reserved' field must start with 'EDF+D' if the recording is interrupted, so not all data records are contiguous. In both cases, the time must be kept in each data record as specified in section 2.2.4. 
% To date only EDF+C is supprorted
element = 'EDF+C';
element = char(element, sprintf('%44s',' ')); element = element(1,:); %Pad to 80 char with spaces
nElements = fwrite(fid, element, 'char'); %write element

%number of Data Records 
element = char(num2str(nRecords), sprintf('%8s',' ')); element = element(1,:);
nElements = fwrite(fid, element, 'char');

%Duration of Data RECORD
element = char(num2str(RecSize), sprintf('%8s',' ')); element = element(1,:);
nElements = fwrite(fid, element, 'char');

%Num Channels
element = char(num2str(nChannels), sprintf('%4s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');

% OK = 256
%% Write EDF Channel Headers
%%%%%Label
% the standard label reads 'EEG Fpz-Cz      '. Further possibilities are listed in the signals table below. 
% http://www.edfplus.info/specs/edftexts.html#signals
for curChan = 1:DataStruct.nChannels
element = DataStruct.Channel(curChan).Name;
if isfield(DataStruct.Channel(curChan),'Number')
  element = fixLabel(element,DataStruct.Channel(curChan).Number,LabelTypes);
else
  element = fixLabel(element,curChan,LabelTypes);  
end
element(16:end) = []; %truncate to 16 char
element = char(element, sprintf('%16s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');
end
%TAL
element = 'EDF Annotations';
element = char(element, sprintf('%16s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');


%%%%%Transducer %This should be the unit like D70-EEE
for curChan = 1:DataStruct.nChannels
    if isfield(DataStruct.Channel(curChan),'Transducer')
        element = DataStruct.Channel(curChan).Transducer;
    elseif isfield(DataStruct.Channel(curChan),'MatrixLoc')
        element = DataStruct.Channel(curChan).MatrixLoc;
    else
        element = '';
    end
    element(81:end) = []; %truncate to 80 char
    element = char(element, sprintf('%80s',' ')); element = element(1,:); 
    nElements = fwrite(fid, element, 'char');
end
%TAL
element = '';
element = char(element, sprintf('%80s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');

%%%%%Physical Dimension (string)
for curChan = 1:DataStruct.nChannels
element = DataStruct.Channel(curChan).Units; element(8:end) = []; %truncate to 8 char
element = char(element, sprintf('%8s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');
end
%TAL
element = '';
element = char(element, sprintf('%8s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');

%%%%Physical min
for curChan = 1:DataStruct.nChannels
PhysicalMin(curChan) = min(DataStruct.Channel(curChan).Data);
element = char(num2str(PhysicalMin(curChan)), sprintf('%8s',' ')); element = element(1,1:8); %force truncation here since MatLAb doesnt thingk (-) is a character
nElements = fwrite(fid, element, 'char');
end
%TAL
element = num2str(0);
element = char(element, sprintf('%8s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');

%%%%Physical Max
for curChan = 1:DataStruct.nChannels
PhysicalMax(curChan) = max(DataStruct.Channel(curChan).Data);
if PhysicalMax(curChan) == PhysicalMin(curChan)
    PhysicalMax(curChan) = PhysicalMin(curChan) +1;
end
element = char(num2str(PhysicalMax(curChan)), sprintf('%8s',' ')); element = element(1,1:8); %force truncation here since MatLAb doesnt thingk (-) is a character
nElements = fwrite(fid, element, 'char');
end
%TAL -The 'Physical maximum' and 'Physical minimum' fields must contain values that differ from each other
element = num2str(1);
element = char(element, sprintf('%8s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');

%%%%Dig Min int 16 = -32768
for curChan = 1:DataStruct.nChannels
element = char(num2str(-32768), sprintf('%8s',' ')); element = element(1,1:8); %force truncation here since MatLAb doesnt thingk (-) is a character
nElements = fwrite(fid, element, 'char');
end
%TAL -The 'Physical maximum' and 'Physical minimum' fields must contain values that differ from each other
element = char(num2str(-32768), sprintf('%8s',' ')); 
element = element(1,1:8); %force truncation here since MatLAb doesnt thingk (-) is a character
nElements = fwrite(fid, element, 'char');

%%%%Dig Max
for curChan = 1:DataStruct.nChannels
element = char(num2str(32767), sprintf('%8s',' ')); element = element(1,1:8); %force truncation here since MatLAb doesnt thingk (-) is a character
nElements = fwrite(fid, element, 'char');
end
%TAL -The 'Physical maximum' and 'Physical minimum' fields must contain values that differ from each other
element = char(num2str(32767), sprintf('%8s',' ')); 
element = element(1,1:8); %force truncation here since MatLAb doesnt thingk (-) is a character
nElements = fwrite(fid, element, 'char');

%%%%Prefiltering
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
    nElements = fwrite(fid, element, 'char');
end
%TAL -The 'Physical maximum' and 'Physical minimum' fields must contain values that differ from each other
element = '';
element = char(element, sprintf('%80s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');

%%%%samples per Data Record - Save in vector for later.....
for curChan = 1:DataStruct.nChannels
recordSamples(curChan) = DataStruct.Channel(curChan).Hz*RecSize;
element = char(num2str(recordSamples(curChan)), sprintf('%8s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');
end
%TAL 
curChan = curChan +1;
recordSamples(curChan) = ReserveTalBytes/2;
element = char(num2str(recordSamples(curChan)), sprintf('%8s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');

%reserved
for curChan = 1:DataStruct.nChannels
element = char(sprintf('%32s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');
end 
%TAL
element = char(sprintf('%32s',' ')); element = element(1,:); 
nElements = fwrite(fid, element, 'char');

%OK 256 + (nSignals * 256)
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
    %loop through each channel
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
        if ~strcmpi(DataStruct.Channel(curChan).Units,'Categorical')
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
    TALString = ['+',num2str( (curRecord -1) * RecSize),char(20),char(20),char(0)];
    try
    for curTAL = 1:(RecSize * DataStruct.Channel(HypnogramChan).Hz)
        TALString = [TALString, '+',num2str( (curRecord -1) * RecSize + (curTAL -1) * 1/DataStruct.Channel(HypnogramChan).Hz ), char(21)...
            num2str(1/DataStruct.Channel(HypnogramChan).Hz),char(20),DataStruct.Channel(HypnogramChan).Labels{LabelCounter},char(20),char(0)];
        LabelCounter = LabelCounter +1;
    end
    catch
        errorstr = ['ERROR: NSB_EDFreader >> Missing TAL Data for Record:',num2str(curRecord)];
        if ~isempty(options.logfile)
            status = NSBlog(options.logfile,errorstr);
        else
            errordlg(errorstr,'NSB_EDFreader');
        end
    end
    TALString = [TALString, char(zeros(1,ReserveTalBytes - length(TALString)))];
    nElements = fwrite(fid, TALString, 'char');
    
    %debug only.
    %WrittenData = WrittenData + nElements;
    %disp(['dataWritten: ',num2str(WrittenData)]);
    %disp(['nElements >> Record#',num2str(curRecord),' TAL = ',num2str(nElements)]);
       

end

close(h)

catch ME
        errorstr = ['ERROR: NSB_EDFreader >> ',ME.message];
        if ~isempty(options.logfile)
            status = NSBlog(options.logfile,errorstr);
        else
            errordlg(errorstr,'NSB_EDFreader');
        end
        fclose(fid);
        return;
    
end
%debug only.
%disp(['Total dataWritten: ',num2str(ftell(fid))]);

fclose(fid);
status = true;


%helper Functions
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
   

function status = NSBlog(LogFileName,LogStr)
% Written By David M. Devilbiss
% NexStep Biomarkers, LLC. (info@nexstepbiomarkers.com)
% December 17 2011, Version 1.0

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

function t = NSB_strcat(varargin)
%NSB_STRCAT Concatenate strings.
%   Rewrite of STRCAT to have better and specific properties.
%
%   COMBINEDSTR = NSB_STRCAT(S1, S2, ..., SN) horizontally concatenates strings
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


