function [ret, msg] = SaveEDF(filename, data, header, type) 

% Àuthor:  Shapkin Andrey, 
% 15-OCT-2012



% Specifications of EDF+ :  http://www.edfplus.info/

% filename - File name
% data - Contains a signals matrix (mõn n - quantity of channels, m -
% signal length) or cell conteins signals data

% header - Contains structure:
%%% 1
% header.patientID local patient identification data:  [patientID Sex(F or M) Birthdate (dd-MMM-yyyy) Name_name] default [X X X X]
% example: NNN-0001 M 01-JAN-2000 Ivanov_Ivav_Ivanovich
% or:
% header.patient   structure of cells whith patient ID:
% header.patient.ID     patient code, default XX
% header.patient.Sex    Sex(F or M), default X
% header.patient.BirthDate birthdate in dd-MMM-yyyy format using the English 3-character abbreviations of the month in capitals default 01-JAN-2000
% header.patient.Name    patient name, defaul X

%%% 2
% header.recordID local recording identification data:  [Startdate dd-MMM-yyyy recordID technician_code equipment_code] default [Startdate X X X X]
% example: Startdate 02-MAR-2002 PSG-1234/2002 Petrov_7180 Telemetry03
% or:
% header.record structure of cells whith record ID:
% header.record.ID   hospital administration code of the investigation, default X
% eader.record.Tech    code specifying the responsible investigator or technician , default X
% header.record.Eq  code specifying the used equipment, default X

%%% 3
%    startdate of recording (dd.mm.yy)
%    header.StartDate  , default = 01.01.00
%%% 4
%    starttime of recording (hh.mm.ss)
%    header.StartTime  , default = 00.00.00
% 5  header.duration        signal block duration in seconds, default =1
% 6  header.labels        - structure of cells with name of channels, by default there will be a numbering of channels
% 7  header.transducer    - transducer type  or structure of cells with transducer type of channels, default=' '
% 8  header.units         - physical dimension or structure of cells with  physical dimension of channels, default=' '
% 9  header.prefilt       - prefiltering or structure of cells with prefiltering of channels, default=' ' -  HP:0.1Hz LP:75Hz N:50Hz
%%% 10 Annotation
% header.annotation.event     structure of cells whith event name 
% header.annotation.duration   vector with event duration (seconds)
% header.annotation.starttime  vector with event startime  (seconds)
%
%
%10/14/2020 DMD cleaned up and added error corrections
%

ret = false; msg = '';
try
%Validate Inputs
if nargin < 4
    edfPlus = true;   %edf+ i.e. with TALs/EDF Annotations Channel
elseif type == 1
    edfPlus = true;   %edf+ i.e. with TALs/EDF Annotations Channel
else
    edfPlus = false;   %edf+ i.e. with TALs/EDF Annotations Channel
end
if ~isfield(header, 'duration') %set data record duration. This is not the best approach
    header.duration=1;
end
if ~iscell(data)                %put each channel into a cell << memory issue
    data=num2cell(data, 1);
end
%Get number of data channels
header.nDataChannels = length(data);

%Validate Sample rates
if numel( header.samplerate ) == 1  %a singleton was used and the sample rate is the same for all channels
    header.samplerate = repmat(header.samplerate, length(data),1);
elseif length(header.samplerate) ~= length(data)
    warning('SaveEDF: The number of samples rates do not corrospond to the number of channels');
    header.samplerate = repmat(header.samplerate(1), length(data),1);
end
%Determine the max number of data records
DataLengths = cellfun(@length,data);
maxDataLengthIDX = find(DataLengths == max(DataLengths), 1, 'first');
header.records=ceil(DataLengths(maxDataLengthIDX) / (header.samplerate(maxDataLengthIDX).*header.duration)); % Quantity of blocks

%% Generate Annotation TAL channel
%EDF annotations contents TALs structure +Ts[21]Ds[20]Event text[20][0]
% + start TALs
% Ts starttime of event in seconds
% [21]Ds duration of event in seconds (optional) [21]=char(21)
% [20]Event text[20] event description  [20]=char(20)
% [0] char(0) end TALs  [0]=char(0)
%The Annotation save in the form of the additional channel [EDF Annotations] containing ASCII in a digital form

if edfPlus == 1
Pa=5;               % quantity of events in one block
                    % Why is this a constant? 
if Pa>length(header.annotation.event)
    Pa=length(header.annotation.event);
end
if length(header.annotation.event)*Pa>header.records % if [quantity of events]*P >> [number of blocks]
    Pa=ceil(length(header.annotation.event)./header.records);
end

%  % TALs forming
Annt=cell(1, header.records); 
for p1=1:header.records
    a=[43 unicode2native(num2str(p1-1)) 20 20 00];
     if Pa.*p1<=length(header.annotation.event)
for p2=Pa.*p1-Pa+1:Pa.*p1
    a=[a 43 unicode2native(num2str(header.annotation.starttime(p2)))];
        if header.annotation.duration(p2)>0
       a=[a 21 unicode2native(num2str(header.annotation.duration(p2)))];
        end
       a=[a 20 unicode2native(header.annotation.event{p2}) 20 00];
end
    end
Annt{p1}=a;
 
    end
fs=cell2mat(cellfun(@length, Annt, 'UniformOutput', false)); 
AnnotationSR=ceil(max(fs)./2).*2; if AnnotationSR<header.samplerate(1), AnnotationSR=header.samplerate(1).*2; end
AnnotationDATA=zeros(AnnotationSR, header.records);
for p1=1:header.records
    AnnotationDATA(1:fs(p1), p1)=Annt{p1};
end

% channel with annotation data
AnnotationDATA=typecast(uint8(AnnotationDATA(:)'), 'int16');
AnnotationSR=length(AnnotationDATA)./header.records; % samplerate annotation channel

data=[data double(AnnotationDATA)];
header.samplerate=[header.samplerate, AnnotationSR];

clear AnnotationDATA AnnotationSR Annt fs;
end

%% Generate EDF(+) header
header.nChannels = length(data);
%signal_length=length(data{1}); 

%1 local patient identification
if ~isfield(header,'patientID')
       header.patientID='';
    if isfield(header,'patient')
     %1 patient code
        if ~isfield(header.patient,'ID')
            header.patientID='X';
        else
            header.patientID=header.patient.ID;
        end
     %2 Sex
        if ~isfield(header.patient,'Sex')
            header.patientID=[header.patientID ' X'];
        else
            header.patientID=[header.patientID ' ' header.patient.Sex];
        end
    %3 BirthDate
        if ~isfield(header.patient,'BirthDate')
            header.patientID=[header.patientID ' X'];
        else
            header.patientID=[header.patientID ' ' upper(header.patient.BirthDate)];
        end
    %4 Patient name 
        if ~isfield(header.patient,'Name')
            header.patientID=[header.patientID ' X'];
        else
            header.patient.Name(double(header.patient.Name)==32)='_';
            header.patientID=[header.patientID ' ' header.patient.Name];
        end
    else
        header.patientID='X X X X';
    end   
end   
header.patientID=header.patientID(:);                                       % what if this is over 80 Chars?

%2 local recording identification
if ~isfield(header,'recordID')
    header.recordID='Startdate';
    
    if ~isfield(header, 'startdate')
        header.recordID=[header.recordID ' X'];
    else
        %F_month={'JAN' 'FEB' 'MAR' 'APR' 'MAY' 'JUN' 'JUL' 'AUG' 'SEP' 'OCT' 'NOV' 'DEC'};
        %header.recordID=[header.recordID ' ' header.startdate(1:2) '-' F_month{str2num(header.startdate(4:5))} '-' header.startdate(7:8)];
        header.recordID=[header.recordID, ' ', upper(datestr(datenum(header.startdate),'dd-mmm-yyyy'))];
    end
    
    if isfield(header,'record')
        %1 hospital administration code of the investigation
        if ~isfield(header.record,'ID')
            header.recordID=[header.recordID ' X'];
        else
            header.recordID=[header.recordID ' ' header.record.ID];
        end
        %2 code specifying the responsible investigator or technician
        if ~isfield(header.record,'Tech')
            header.recordID=[header.recordID ' X'];
        else
            header.recordID=[header.recordID ' ' header.record.Tech];
        end
        %3 code specifying the used equipment, default X
        if ~isfield(header.record,'Eq')
            header.recordID=[header.recordID ' X'];
        else
            header.recordID=[header.recordID ' ' header.record.Eq];
        end
    else
        header.recordID=[header.recordID ' X X X'];
    end
end
header.recordID= header.recordID(:);                                       % what if this is over 80 Chars?

%3 startdate of recording (dd.mm.yy)
if ~isfield(header, 'startdate')
    header.startdate='01.01.00';
else
    header.startdate=  datestr(datenum(header.startdate),'dd.mm.yy');
end
header.startdate=header.startdate(:);

%4 starttime of recording (hh.mm.ss)
if ~isfield(header, 'starttime')
    header.starttime='00.00.00';
else
    header.starttime=datestr(datenum(header.starttime),'HH.MM.SS');
end
header.starttime=header.starttime(:);

%%%%%%%%%%%%%% Start forming channel header
%5 labels %OK
if ~isfield(header, 'labels')                                           
    header.labels=cellstr(num2str([1:header.nDataChannels]'));
end
if edfPlus
    header.labels{end+1}='EDF Annotations';% annotation channel
end
labels = char(32*ones(header.nChannels, 16));

for n=1:header.nChannels
    if isempty(header.labels{n}), header.labels{n}=' '; end                     %fill cell if empty
    if length(header.labels{n})>16,header.labels{n}=header.labels{n}(1:16);end  %truncate label if longer
    labels(n,1:length(header.labels{n})) = header.labels{n};                    %copy to labels
end
header.labels=labels';
header.labels=header.labels(:);

%6 transducer type %OK
if ~isfield(header, 'transducer')
    header.transducer={' '};
end
if ~iscell(header.transducer)
    header.transducer={header.transducer}; 
end
if length(header.transducer)==1                                        %If input is Singleton replicate across channels
    header.transducer(1:header.nDataChannels)=header.transducer;            %<<<<<<<<<<<<<<<<<<<<<
end
if edfPlus
    header.transducer{end+1}=' ';% annotation channel
end
transducer=char(32*ones(header.nChannels, 80));                         % what if this is over 80 Chars?

for n=1:header.nChannels
    if isempty(header.transducer{n}), header.transducer{n}=' '; end
    if length(header.transducer{n})>80,header.transducer{n}=header.transducer{n}(1:80);end
    transducer(n,1:length(header.transducer{n})) = header.transducer{n};
end
header.transducer=transducer';
header.transducer=header.transducer(:);

%7 units %ok
if ~isfield(header, 'units')
    header.units={' '};
end
if ~iscell(header.units), header.units={header.units}; end
if length(header.units)==1                                        %If input is Singleton replicate across channels
    header.units(1:header.nDataChannels)=header.units;                   %<<<<<<<<<<<<<<<<<<<<<
end
if edfPlus
    header.units{end+1}=' ';% annotation channel
end
units=char(32*ones(header.nChannels, 8));                            %<<<<<<<<<<<<<<<<<<<<<

for n=1:header.nChannels                                             %<<<<<<<<<<<<<<<<<<<<<
    if isempty(header.units{n}), header.units{n}=' '; end
    if length(header.units{n})>8,header.units{n}=header.units{n}(1:8);end
    units(n,1:length(header.units{n})) = header.units{n};
end
units(double(units)<32)=' ';
units(double(units)>126)=' ';

header.units=units';
header.units=header.units(:);


%8 prefiltering
if ~isfield(header, 'prefilt')
    header.prefilt={' '};
end
if ~iscell(header.prefilt), header.prefilt={header.prefilt}; end
if length(header.prefilt)==1                                        %If input is Singleton replicate across channels
    header.prefilt(1:header.nDataChannels)=header.prefilt;               %this is broken!%<<<<<<<<<<<<<<<<<<<<<
end
if edfPlus
    header.prefilt{end+1}=' ';% annotation channel
end

prefilt=char(32*ones(header.nChannels, 80));
for n=1:header.nChannels
    if isempty(header.prefilt{n}), header.prefilt{n}=' '; end
    if length(header.prefilt{n})>80,header.prefilt{n}=header.prefilt{n}(1:80);end
    prefilt(n,1:length(header.prefilt{n})) = header.prefilt{n};
end
header.prefilt=prefilt';
header.prefilt=header.prefilt(:);

%9 samplerate (number of samples per data record) this was addressed above %ok
samplerate=header.samplerate;
header.samplerate=sprintf('%-8i', ceil(header.samplerate .* header.duration))';
header.samplerate=header.samplerate(:);

% physical maximum                                                      %<< this is different from above and I like this approach
if ~isfield(header, 'physmax')
    header.physmax = 32767;
elseif isempty(header.physmax)
    header.physmax = 32767;
end
if iscell(header.physmax), header.physmax=header.physmax{:}; end
if length(header.physmax)==1
   header.physmax(1:header.nDataChannels)=header.physmax;
end
if edfPlus
    header.physmax(end+1)=1;% annotation channel
end

% physical minimum 
if ~isfield(header, 'physmin')
    header.physmin = -32768;
elseif isempty(header.physmin)
    header.physmin = -32768;
end
if iscell(header.physmin), header.physmin=header.physmin{:}; end
if length(header.physmin)==1
   header.physmin(1:header.nDataChannels)=header.physmin;
end
if edfPlus
    header.physmin(end+1) = -1;% annotation channel
end

% digital maximum 
if ~isfield(header, 'digmax')
    header.digmax = 32767;
elseif isempty(header.digmax)
    header.digmax = 32767;
end
if iscell(header.digmax), header.digmax=header.digmax{:}; end
if length(header.digmax)==1
   header.digmax(1:header.nDataChannels)=header.digmax;
end
if edfPlus
    header.digmax(end+1) = 32767;% annotation channel
end

% digital minimum 
if ~isfield(header, 'digmin')
    header.digmin = -32768;
elseif isempty(header.digmin)
    header.digmin = -32768;
end
if iscell(header.digmin), header.digmin=header.digmin{:}; end
if length(header.digmin)==1
   header.digmin(1:header.nDataChannels)=header.digmin;
end
if edfPlus
    header.digmin(end+1) = -32768;% annotation channel
end

header.digmin = sprintf('%-8i', int16(header.digmin))'; % digital minimum
header.digmax = sprintf('%-8i', int16(header.digmax))';  %digital maximum
header.physmin = sprintf('%-8i', int16(header.physmin))';  %physical minimum  
header.physmax = sprintf('%-8i', int16(header.physmax))'; %physical maximum  

% gain = (physical maximum - physical minimum) /(digital maximum - digital minimum)
% So 32767 - -32768 = 16bit ADC
% 

%Scale=32767/maxdata;
%data(1:end-1)=cellfun(@(x) x.*Scale, data(1:end-1), 'UniformOutput', false);
catch ME
    msg = [ME.message,' in ',ME.stack(1).name,' Line: ',num2str(ME.stack(1).line)];
    return;
end  
%% PART 3: forming of data
%Structure of the data in format EDF:

%[block1 block2 .. , block Pn], where Pn is quantity of blocks  Pn=header.records
% Block structure:
% [(d seconds of 1 channel) (d seconds of 2 channel) ... (d seconds of Ñh channel)], Where Ñh - quantity of channels, d - duration of the block
% Ch = header.nChannels
% d = header.duration

% detrend
%data(1:end-1)=cellfun(@detrend, data(1:end-1), 'UniformOutput', false);


%%%%%%%%%%%%%%%%%
% This section is REALLY memory intense and is the easy way if you have
% GB/TB of memory.. However, matlab is bad at this
try
    %Step 1 for each channel buffer data into "RecordLength" blocks
    % this is generally fine for smaller files
    for p1=1:length(data)
        data{p1}=(buffer(data{p1}, ceil(samplerate(p1).*header.duration), 0));
    end
catch ME
    msg = [ME.message,' in ',ME.stack(1).name,' Line: ',num2str(ME.stack(1).line)];
    warning('SaveEDF: Out of Memory converting data to int16');
    %if this fails convert all data to single. This should work since all EDF values are single precision
    for curChan = 1:length(data)
        data{curChan} = int16(data{curChan});
    end
    for p1=1:length(data)
        data{p1}=(buffer(data{p1}, ceil(samplerate(p1).*header.duration), 0));
    end
    DATAout=cell2mat(data');
    DATAout=DATAout(:);
end

try
    %Step 2 Stack and read out data into a linear stream so that it is
    %[CH1-rec1; Ch2-rec1;...Ch1-rec2; Ch2-rec2;...]
    %The cell2Mat function will bail if it is a LARGE data set
    DATAout=cell2mat(data');
    DATAout=DATAout(:);
    
catch ME
    msg = [ME.message,' in ',ME.stack(1).name,' Line: ',num2str(ME.stack(1).line)];
    warning('SaveEDF: Out of Memory converting data to int16');
    % DMD there are a few ways to handle this:
    %if this fails convert all data to single. This should work since all EDF values are single precision
    for curChan = 1:length(data)
        data{curChan} = int16(data{curChan});
    end
    try
        DATAout=cell2mat(data');
        DATAout=DATAout(:);
        
    catch ME2
        % if it all fails
        %2) use a loop to assemble these data
        msg = [ME2.message,' in ',ME2.stack(1).name,' Line: ',num2str(ME2.stack(1).line)];
        warning('SaveEDF: Out of Memory using loop to assemble data (This is slow)');
        DATAout = [];
        nFrags = size(data{1},2);
        txt = fprintf('Processing datarecord: 0 of %d', nFrags);
        for curFrame = 1:nFrags
            fprintf(repmat('\b',1,txt))
            txt = fprintf('Processing datarecord: %d of %d\n', curFrame, nFrags);
            for curChan = 1:length(data)
                DATAout = [DATAout; data{curChan}(:,curFrame)];
            end
        end
    end
end

try    
%% SAVE DATA  
fid = fopen(filename, 'wb', 'ieee-le');
%%%%%% PART4: save header
 % 8 ascii : version of this data format (0)
fprintf(fid, ['0       ']);   
% 80 ascii : local patient identification
fprintf(fid, '%-80s', [header.patientID]);
% 80 ascii : local recording identification
fprintf(fid,'%-80s', [header.recordID]);
% 8 ascii : startdate of recording (dd.mm.yy)
fprintf(fid, '%8s', header.startdate); 
% 8 ascii : starttime of recording (hh.mm.ss)
fprintf(fid, '%8s', header.starttime);
% 8 ascii : number of bytes in header record
fprintf(fid, '%-8s', num2str(256*(1+header.nChannels)));  % number of bytes in header %<<<<<<<<<<<<<<<<<<<<<
% 44 ascii : reserved
if edfPlus == 1
fprintf(fid, '%-44s', 'EDF+C'); % reserved (44 spaces)
else
    fprintf(fid, '%-44s', 'EDF'); % reserved (44 spaces)
end
% 8 ascii : number of data records (-1 if unknown)
fprintf(fid, '%-8i', header.records);  
% 8 ascii : duration of a data record, in seconds
header.duration = sprintf('%8f', header.duration);
header.duration(8+1:end) = [];
fprintf(fid, '%8s', header.duration);  % header.duration=1 seconds;
% 4 ascii : number of signals (ns) in data record
fprintf(fid, '%-4s', num2str(header.nChannels));                                         %<<<<<<<<<<<<<<<<<<<<<
%256 bytes
% ns * 16 ascii : ns * label (e.g. EEG FpzCz or Body temp)
fwrite(fid, header.labels, 'char*1'); 
% ns * 80 ascii : ns * transducer type (e.g. AgAgCl electrode)
fwrite(fid, header.transducer, 'char*1'); 
% ns * 8 ascii : ns * physical dimension (e.g. uV or degreeC)
fwrite(fid, header.units, 'char*1'); 
% ns * 8 ascii : ns * physical minimum (e.g. -500 or 34)
fwrite(fid, header.physmin, 'char*1'); 
% ns * 8 ascii : ns * physical maximum (e.g. 500 or 40)
fwrite(fid, header.physmax, 'char*1'); 
% ns * 8 ascii : ns * digital minimum (e.g. -2048)
fwrite(fid, header.digmin, 'char*1'); 
 % ns * 8 ascii : ns * digital maximum (e.g. 2047)
fwrite(fid, header.digmax, 'char*1');
% ns * 80 ascii : ns * prefiltering (e.g. HP:0.1Hz LP:75Hz)
fwrite(fid, header.prefilt, 'char*1'); 
% ns * 8 ascii : ns * nr of samples in each data record
fwrite(fid, header.samplerate, 'char*1'); 
% ns * 32 ascii : ns * reserved
fwrite(fid, repmat(' ', 32.*header.nChannels, 1), 'char*1'); % reserverd (32 spaces / channel)%<<<<<<<<<<<<<<<<<<<<<
%n * 256
%%%%%% PART5: save data
fwrite(fid, DATAout, 'int16');
fclose(fid);
catch ME
    fclose(fid);
    msg = [ME.message,' in ',ME.stack(1).name,' Line: ',num2str(ME.stack(1).line)];
    return;
end
ret = true;
