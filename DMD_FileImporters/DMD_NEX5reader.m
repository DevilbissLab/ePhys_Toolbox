function [nexFile, status] = DMD_NEX5reader(fileName,readType,opts)
% [nexFile, status] = DMD_NEXreader(fileName,readType)
%
% This file was originally written by Nex Technologies and likely copyrighted.
% See http://www.neuroexplorer.com/code.html but no licence was Identified
%
% Modified by David M. Devilbiss (15Oct2020) for Full Read of Data
%
% -----------------------------Begin Neuroexplorer Comments
% [nexFile] = readNexFile(fileName) -- read .nex5 file and return file data
%             in nexFile structure
%
% INPUT:
%   fileName - if empty string, will use File Open dialog
%
% OUTPUT:
%   nexFile - a structure containing .nex file data
%   nexFile.version - file version
%   nexFile.comment - file comment
%   nexFile.freq - file timestamp frequency (Hz)
%   nexFile.tbeg - beginning of recording session (in seconds)
%   nexFile.tend - end of recording session (in seconds)
%   nexFile.metadata - file metadata as a string in json format
%
%   nexFile.neurons - array of neuron structures
%           neurons{i}.name - name of a neuron variable
%           neurons{i}.timestamps - array of neuron timestamps (in seconds)
%               to access timestamps for neuron 2 use {n} notation:
%               nexFile.neurons{2}.timestamps
%
%   nexFile.events - array of event structures
%           events{i}.name - name of event variable
%           events{i}.timestamps - array of event timestamps (in seconds)
%
%   nexFile.intervals - array of interval structures
%           intervals{i}.name - name of interval variable
%           intervals{i}.intStarts - array of interval starts (in seconds)
%           intervals{i}.intEnds - array of interval ends (in seconds)
%
%   nexFile.waves - array of wave structures
%           waves{i}.name - name of waveform variable
%           waves{i}.NPointsWave - number of data points in each wave
%           waves{i}.WFrequency - A/D frequency for wave data points
%           waves{i}.timestamps - array of wave timestamps (in seconds)
%           waves{i}.waveforms - matrix of waveforms (in milliVolts), each
%                                waveform is a column 
%
%   nexFile.contvars - array of continuous variable structures
%           contvars{i}.name - name of continuous variable
%           contvars{i}.ADFrequency - A/D frequency for data points
%
%           Continuous (a/d) data for one channel is allowed to have gaps 
%           in the recording (for example, if recording was paused, etc.).
%           Therefore, continuous data is stored in fragments. 
%           Each fragment has a timestamp and an index of the first data 
%           point of the fragment (data values for all fragments are stored
%           in one array and the index indicates the start of the fragment
%           data in this array).
%           The timestamp corresponds to the time of recording of 
%           the first a/d value in this fragment.
%
%           contvars{i}.timestamps - array of timestamps (fragments start times in seconds)
%           contvars{i}.fragmentStarts - array of start indexes for fragments in contvar.data array
%           contvars{i}.data - array of data points (in milliVolts)
%
%   nexFile.popvectors - array of population vector structures
%           popvectors{i}.name - name of population vector variable
%           popvectors{i}.weights - array of population vector weights
%
%   nexFile.markers - array of marker structures
%           markers{i}.name - name of marker variable
%           markers{i}.timestamps - array of marker timestamps (in seconds)
%           markers{i}.values - array of marker value structures
%               markers{i}.values{j}.name - name of marker value 
%               markers{i}.values{j}.strings - array of marker value strings 
%                     (if values are stored as strings in the file)
%               markers{i}.values{j}.numericValues - numeric marker values
%                     (if values are stored as numbers in the file)
%

nexFile = [];
status = false;

switch nargin
    case 0
        [fname, pathname] = uigetfile( {'.nex5'}, 'Select a NeuroExplorer5 file');
        fileName = strcat(pathname, fname);
        [~, ~, fext] = fileparts(fileName); %identify Nex Type
        readType = 0:6;
        opts.progress = true;
    case 1
        if isempty(fileName)
            [fname, pathname] = uigetfile( {'.nex5'}, 'Select a NeuroExplorer5 file');
            fileName = strcat(pathname, fname);
        end
        [pathname, fname, fext] = fileparts(fileName);
        fname = [fname,fext];
        readType = 0:6;
        opts.progress = true;
    case 2
        [pathname, fname, fext] = fileparts(fileName);
        fname = [fname,fext];
        opts.progress = true;
    case 3
        [pathname, fname, fext] = fileparts(fileName);
        fname = [fname,fext];
        if ~isfield(opts,'progress')
            opts.progress = true;
        end
end

if strcmpi(fext, '.nex')
    [nexFile, status] = DMD_NEXreader(fileName,readType,opts);
    return;
end

fid = fopen(fileName, 'r', 'l','US-ASCII'); %Alex suggestion to ensure that the files are read correctly
% on big-endian systems, such as Mac.
if(fid == -1)
    error 'Unable to open file'
    return;
end

if opts.progress
    warning off; %may be tex issues with underscores
    hWaitBar = waitbar(0, ['Please Wait, Opening: ',regexprep(fname,'[_^]',' ')]);
    warning on;
end

magic = fread(fid, 1, 'int32');
if magic ~= 894977358
    error 'The file is not a valid .nex file'
end
nexFile.Version = fread(fid, 1, 'int32');
nexFile.SubjectID = '';
nexFile.Comment = deblank(char(fread(fid, 256, 'char')'));
nexFile.FileFormat = '.nex5';
nexFile.Hz = fread(fid, 1, 'double');
tbeg = fread(fid, 1, 'int64')./nexFile.Hz;
FileInfo = dir(fileName);
nexFile.nChannels = fread(fid, 1, 'int32');

metaOffset = fread(fid, 1, 'uint64');
tend = fread(fid, 1, 'int64')./nexFile.Hz;
if nexFile.Version < 501
    tend = 0;        
end

nexFile.StartDate = datenum([0 0 0 0 0 tbeg]); %Nex Does not store real time
nexFile.nSeconds = tend - tbeg;

% skip padding
fseek(fid, 56, 'cof');    

neuronCount = 0;
eventCount = 0;
intervalCount = 0;
waveCount = 0;
popCount = 0;
contCount = 0;
markerCount = 0;

% read all variables
for i=1:nexFile.nChannels
    type = fread(fid, 1, 'int32');
    varVersion = fread(fid, 1, 'int32');
    name = deblank(char(fread(fid, 64, 'char')'));
    offset = fread(fid, 1, 'uint64');
    n = fread(fid, 1, 'int64');
    % WireNumber, UnitNumber, Gain, Filter, XPos, YPos moved
    tsDataType = fread(fid, 1, 'int32');
    contDataType = fread(fid, 1, 'int32');
   
    WFrequency = fread(fid, 1, 'double'); % wf sampling fr.
    units = fread(fid, 32, '*char')';
    units(end+1) = 0;
    units = units(1:min(find(units==0))-1);
    
    ADtoMV  = fread(fid, 1, 'double'); % coeff to convert from AD values to Millivolts.
    MVOfffset = fread(fid, 1, 'double'); % coeff to shift AD values in Millivolts: mv = raw*ADtoMV+MVOfffset
    NPointsWave = fread(fid, 1, 'uint64'); % number of points in each wave
    PrethresholdTime = fread(fid, 1, 'double'); % if waveform timestamp in seconds is t,
    % then the timestamp of the first point of waveform is t - PrethresholdTimeInSeconds
    
    markerDataType = fread(fid, 1, 'int32');
    NMarkers = fread(fid, 1, 'int32'); % how many values are associated with each marker
    MarkerLength = fread(fid, 1, 'int32'); % how many characters are in each marker value
    contFragmentStartDataType = fread(fid, 1, 'int32');
    
    Units = 'mV';
    %60/52 char pad dealt with below
    filePosition = ftell(fid);
    if ismember(type, readType)
        switch type
            case 0 % neuron
                neuronCount = neuronCount+1;
                nexFile.neurons(neuronCount,1).Name = name;
                % Initially i wanted this to be the nax channel number and
                % wire nnumber but in earlier versions this seems to be 0;
                % The other option is to index each type individually but
                % they wont have a uid. so we are using the raw channel
                % number.
                nexFile.neurons(neuronCount,1).ChNumber = i;
                nexFile.neurons(neuronCount,1).Units = '';
                
                fseek(fid, offset, 'bof');
                if ( tsDataType == 0 )
                    nexFile.neurons(neuronCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                else
                    nexFile.neurons(neuronCount,1).ts = fread(fid, [n 1], 'int64')./nexFile.Hz;
                end
                
                %added bonus data for ease of re-writing
                %if Nex ver is <=100 Wire and Unit Number = 0
                nexFile.neurons(neuronCount,1).type = type;
                nexFile.neurons(neuronCount,1).varVersion = varVersion;
                nexFile.neurons(neuronCount,1).FilePosDataOffset = offset;
                nexFile.neurons(neuronCount,1).nEvents = n;
                nexFile.neurons(neuronCount,1).tsDataType = tsDataType;
                nexFile.neurons(neuronCount,1).contDataType = contDataType;
                nexFile.neurons(neuronCount,1).contFragStartDataType = contFragmentStartDataType;
                nexFile.neurons(neuronCount,1).markerDataType = markerDataType;
                nexFile.neurons(neuronCount,1).Nex5Units = units;
                %nexFile.neurons(neuronCount,1).WireNumber = WireNumber;
                %nexFile.neurons(neuronCount,1).UnitNumber = UnitNumber;
                %nexFile.neurons(neuronCount,1).Gain = Gain;
                %nexFile.neurons(neuronCount,1).Filter = Filter;
                %nexFile.neurons(neuronCount,1).XPos = XPos;
                %nexFile.neurons(neuronCount,1).YPos = YPos;
                nexFile.neurons(neuronCount,1).Hz = WFrequency;
                nexFile.neurons(neuronCount,1).ADtoMV = ADtoMV;
                nexFile.neurons(neuronCount,1).NPointsWave = NPointsWave;
                nexFile.neurons(neuronCount,1).NMarkers = NMarkers;
                nexFile.neurons(neuronCount,1).MarkerLength = MarkerLength;
                nexFile.neurons(neuronCount,1).MVOfffset = MVOfffset;
                nexFile.neurons(neuronCount,1).PrethresholdTime = PrethresholdTime;
                
            case 1 % event
                eventCount = eventCount+1;
                nexFile.events(eventCount,1).Name = name;
                % Initially i wanted this to be the nax channel number and
                % wire nnumber but in earlier versions this seems to be 0;
                % The other option is to index each type individually but
                % they wont have a uid. so we are using the raw channel
                % number.
                nexFile.events(eventCount,1).ChNumber = i;
                nexFile.events(eventCount,1).Units = '';
                
                fseek(fid, offset, 'bof');
                if ( tsDataType == 0 )
                    nexFile.events(eventCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                else
                    nexFile.events(eventCount,1).ts = fread(fid, [n 1], 'int64')./nexFile.Hz;
                end
                
                %added bonus data for ease of re-writing
                nexFile.events(eventCount,1).type = type;
                nexFile.events(eventCount,1).varVersion = varVersion;
                nexFile.events(eventCount,1).FilePosDataOffset = offset;
                nexFile.events(eventCount,1).nEvents = n;
                nexFile.events(eventCount,1).tsDataType = tsDataType;
                nexFile.events(eventCount,1).contDataType = contDataType;
                nexFile.events(eventCount,1).contFragStartDataType = contFragmentStartDataType;
                nexFile.events(eventCount,1).markerDataType = markerDataType;
                nexFile.events(eventCount,1).Nex5Units = units;
                %nexFile.events(eventCount,1).WireNumber = WireNumber;
                %nexFile.events(eventCount,1).UnitNumber = UnitNumber;
                %nexFile.events(eventCount,1).Gain = Gain;
                %nexFile.events(eventCount,1).Filter = Filter;
                %nexFile.events(eventCount,1).XPos = XPos;
                %nexFile.events(eventCount,1).YPos = YPos;
                nexFile.events(eventCount,1).Hz = WFrequency;
                nexFile.events(eventCount,1).ADtoMV = ADtoMV;
                nexFile.events(eventCount,1).NPointsWave = NPointsWave;
                nexFile.events(eventCount,1).NMarkers = NMarkers;
                nexFile.events(eventCount,1).MarkerLength = MarkerLength;
                nexFile.events(eventCount,1).MVOfffset = MVOfffset;
                nexFile.events(eventCount,1).PrethresholdTime = PrethresholdTime;
                
            case 2 % interval
                intervalCount = intervalCount+1;
                nexFile.intervals(intervalCount,1).Name = name;
                % Initially i wanted this to be the nax channel number and
                % wire nnumber but in earlier versions this seems to be 0;
                % The other option is to index each type individually but
                % they wont have a uid. so we are using the raw channel
                % number.
                nexFile.intervals(intervalCount,1).ChNumber = i;
                nexFile.intervals(intervalCount,1).Units = '';
                
                fseek(fid, offset, 'bof');
                if ( tsDataType == 0 )
                    nexFile.intervals(intervalCount,1).intStarts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                    nexFile.intervals(intervalCount,1).intEnds = fread(fid, [n 1], 'int32')./nexFile.Hz;
                else
                    nexFile.intervals(intervalCount,1).intStarts = fread(fid, [n 1], 'int64')./nexFile.Hz;
                    nexFile.intervals(intervalCount,1).intEnds = fread(fid, [n 1], 'int64')./nexFile.Hz;
                end
                                
                %added bonus data for ease of re-writing
                nexFile.intervals(intervalCount,1).type = type;
                nexFile.intervals(intervalCount,1).varVersion = varVersion;
                nexFile.intervals(intervalCount,1).FilePosDataOffset = offset;
                nexFile.intervals(intervalCount,1).nEvents = n;
                nexFile.intervals(intervalCount,1).tsDataType = tsDataType;
                nexFile.intervals(intervalCount,1).contDataType = contDataType;
                nexFile.intervals(intervalCount,1).contFragStartDataType = contFragmentStartDataType;
                nexFile.intervals(intervalCount,1).markerDataType = markerDataType;
                nexFile.intervals(intervalCount,1).Nex5Units = units;
                %nexFile.intervals(intervalCount,1).WireNumber = WireNumber;
                %nexFile.intervals(intervalCount,1).UnitNumber = UnitNumber;
                %nexFile.intervals(intervalCount,1).Gain = Gain;
                %nexFile.intervals(intervalCount,1).Filter = Filter;
                %nexFile.intervals(intervalCount,1).XPos = XPos;
                %nexFile.intervals(intervalCount,1).YPos = YPos;
                nexFile.intervals(intervalCount,1).Hz = WFrequency;
                nexFile.intervals(intervalCount,1).ADtoMV = ADtoMV;
                nexFile.intervals(intervalCount,1).NPointsWave = NPointsWave;
                nexFile.intervals(intervalCount,1).NMarkers = NMarkers;
                nexFile.intervals(intervalCount,1).MarkerLength = MarkerLength;
                nexFile.intervals(intervalCount,1).MVOfffset = MVOfffset;
                nexFile.intervals(intervalCount,1).PrethresholdTime = PrethresholdTime;
                
            case 3 % waveform
                waveCount = waveCount+1;
                nexFile.waves(waveCount,1).Name = name;
                % Initially i wanted this to be the nax channel number and
                % wire nnumber but in earlier versions this seems to be 0;
                % The other option is to index each type individually but
                % they wont have a uid. so we are using the raw channel
                % number.
                nexFile.waves(waveCount,1).ChNumber = i;
                nexFile.waves(waveCount,1).Units = Units;
                
                nexFile.waves(waveCount,1).NPointsWave = NPointsWave;
                nexFile.waves(waveCount,1).Hz = WFrequency;
                nexFile.waves(waveCount,1).ADtoMV = ADtoMV;
                if nexFile.Version > 104
                    nexFile.waves(waveCount,1).MVOfffset = MVOfffset;
                else
                    nexFile.waves{waveCount,1}.MVOfffset = 0;
                end
                if (varVersion > 101) && (nexFile.Version >= 106)
                    nexFile.waves(waveCount,1).PrethresholdTime = PrethresholdTime;
                else
                    nexFile.waves(waveCount,1).PrethresholdTime = 0;
                end
                
                fseek(fid, offset, 'bof');
                if ( tsDataType == 0 )
                    nexFile.waves(waveCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                    nexFile.waves(waveCount,1).waveforms = fread(fid, [NPointsWave n], 'int16').*ADtoMV + MVOfffset;
                else
                    nexFile.waves(waveCount,1).ts = fread(fid, [n 1], 'int64')./nexFile.Hz;
                    nexFile.waves(waveCount,1).waveforms = fread(fid, [NPointsWave n], 'float32').*ADtoMV + MVOfffset;
                end

                
                %added bonus data for ease of re-writing
                %if Nex ver is <=100 Wire and Unit Number = 0
                nexFile.waves(waveCount,1).type = type;
                nexFile.waves(waveCount,1).varVersion = varVersion;
                nexFile.waves(waveCount,1).FilePosDataOffset = offset;
                nexFile.waves(waveCount,1).nEvents = n;
                nexFile.waves(waveCount,1).tsDataType = tsDataType;
                nexFile.waves(waveCount,1).contDataType = contDataType;
                nexFile.waves(waveCount,1).contFragStartDataType = contFragmentStartDataType;
                nexFile.waves(waveCount,1).markerDataType = markerDataType;
                nexFile.waves(waveCount,1).Nex5Units = units;
                %nexFile.waves(waveCount,1).WireNumber = WireNumber;
                %nexFile.waves(waveCount,1).UnitNumber = UnitNumber;
                %nexFile.waves(waveCount,1).Gain = Gain;
                %nexFile.waves(waveCount,1).Filter = Filter;
                %nexFile.waves(waveCount,1).XPos = XPos;
                %nexFile.waves(waveCount,1).YPos = YPos;
                nexFile.waves(waveCount,1).NMarkers = NMarkers;
                nexFile.waves(waveCount,1).MarkerLength = MarkerLength;

                
            case 4 % population vector
                popCount = popCount+1;
                nexFile.popvectors(popCount,1).Name = name;
                % Initially i wanted this to be the nax channel number and
                % wire nnumber but in earlier versions this seems to be 0;
                % The other option is to index each type individually but
                % they wont have a uid. so we are using the raw channel
                % number.
                nexFile.popvectors(popCount,1).ChNumber = i;
                nexFile.popvectors(popCount,1).Units = '';
                
                fseek(fid, offset, 'bof');
                nexFile.popvectors(popCount,1).weights = fread(fid, [n 1], 'double');
                
                %added bonus data for ease of re-writing
                nexFile.popvectors(popCount,1).type = type;
                nexFile.popvectors(popCount,1).varVersion = varVersion;
                nexFile.popvectors(popCount,1).FilePosDataOffset = offset;
                nexFile.popvectors(popCount,1).nEvents = n;
                nexFile.popvectors(popCount,1).tsDataType = tsDataType;
                nexFile.popvectors(popCount,1).contDataType = contDataType;
                nexFile.popvectors(popCount,1).contFragStartDataType = contFragmentStartDataType;
                nexFile.popvectors(popCount,1).markerDataType = markerDataType;
                nexFile.popvectors(popCount,1).Nex5Units = units;
                %nexFile.popvectors(popCount,1).WireNumber = WireNumber;
                %nexFile.popvectors(popCount,1).UnitNumber = UnitNumber;
                %nexFile.popvectors(popCount,1).Gain = Gain;
                %nexFile.popvectors(popCount,1).Filter = Filter;
                %nexFile.popvectors(popCount,1).XPos = XPos;
                %nexFile.popvectors(popCount,1).YPos = YPos;
                nexFile.popvectors(popCount,1).Hz = WFrequency;
                nexFile.popvectors(popCount,1).ADtoMV = ADtoMV;
                nexFile.popvectors(popCount,1).NPointsWave = NPointsWave;
                nexFile.popvectors(popCount,1).NMarkers = NMarkers;
                nexFile.popvectors(popCount,1).MarkerLength = MarkerLength;
                nexFile.popvectors(popCount,1).MVOfffset = MVOfffset;
                nexFile.popvectors(popCount,1).PrethresholdTime = PrethresholdTime;
                
            case 5 % continuous variable
                contCount = contCount+1;
                nexFile.Channel(contCount,1).Name = name;
                % Initially i wanted this to be the nax channel number and
                % wire nnumber but in earlier versions this seems to be 0;
                % The other option is to index each type individually but
                % they wont have a uid. so we are using the raw channel
                % number.
                %nexFile.neurons(neuronCount,1).ChNumber = i;
                %<<Apr4,2014fails if no neurons because read type does not
                %include neurons
                nexFile.Channel(contCount,1).ChNumber = i;
                nexFile.Channel(contCount,1).Units = Units;
                
                nexFile.Channel(contCount,1).Hz = WFrequency;
                nexFile.Channel(contCount,1).ADtoMV = ADtoMV;
                if nexFile.Version > 104
                    nexFile.Channel(contCount,1).MVOfffset = MVOfffset;
                else
                    nexFile.Channel(contCount,1).MVOfffset = 0;
                end
                
                fseek(fid, offset, 'bof');
                if ( tsDataType == 0 )
                    nexFile.Channel(contCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                    nexFile.Channel(contCount,1).fragmentStarts = fread(fid, [n 1], 'int32') + 1;
                    nexFile.Channel(contCount,1).Data = fread(fid, [NPointsWave 1], 'int16').*ADtoMV + MVOfffset;
                else
                    nexFile.Channel(contCount,1).ts = fread(fid, [n 1], 'int64')./nexFile.Hz;
                    nexFile.Channel(contCount,1).fragmentStarts = fread(fid, [n 1], 'uint64') + 1;
                    nexFile.Channel(contCount,1).Data = fread(fid, [NPointsWave 1], 'float32').*ADtoMV + MVOfffset;
                end
                %added bonus data for ease of re-writing
                nexFile.Channel(contCount,1).type = type;
                nexFile.Channel(contCount,1).varVersion = varVersion;
                nexFile.Channel(contCount,1).FilePosDataOffset = offset;
                nexFile.Channel(contCount,1).nEvents = n;
                nexFile.Channel(contCount,1).tsDataType = tsDataType;
                nexFile.Channel(contCount,1).contDataType = contDataType;
                nexFile.Channel(contCount,1).contFragStartDataType = contFragmentStartDataType;
                nexFile.Channel(contCount,1).markerDataType = markerDataType;
                nexFile.Channel(contCount,1).Nex5Units = units;
                %nexFile.Channel(contCount,1).WireNumber = WireNumber;
                %nexFile.Channel(contCount,1).UnitNumber = UnitNumber;
                %nexFile.Channel(contCount,1).Gain = Gain;
                %nexFile.Channel(contCount,1).Filter = Filter;
                %nexFile.Channel(contCount,1).XPos = XPos;
                %nexFile.Channel(contCount,1).YPos = YPos;
                nexFile.Channel(contCount,1).NPointsWave = NPointsWave;
                nexFile.Channel(contCount,1).NMarkers = NMarkers;
                nexFile.Channel(contCount,1).MarkerLength = MarkerLength;
                nexFile.Channel(contCount,1).PrethresholdTime = PrethresholdTime;
                
            case 6 % marker
                markerCount = markerCount+1;
                nexFile.markers(markerCount,1).Name = name;
                % Initially i wanted this to be the nax channel number and
                % wire nnumber but in earlier versions this seems to be 0;
                % The other option is to index each type individually but
                % they wont have a uid. so we are using the raw channel
                % number.
                nexFile.markers(markerCount,1).ChNumber = i;
                nexFile.markers(markerCount,1).Units = '';
                
                fseek(fid, offset, 'bof');
                if ( tsDataType == 0 )
                    nexFile.markers(markerCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                else
                    nexFile.markers(markerCount,1).ts = fread(fid, [n 1], 'int64')./nexFile.Hz;
                end
                
                for i=1:NMarkers
                    nexFile.markers(markerCount,1).values{i,1}.Name = deblank(char(fread(fid, 64, 'char')'));
                    if ( markerDataType == 0 )
                    for p = 1:n
                        nexFile.markers(markerCount,1).values{i,1}.strings{p, 1} = deblank(char(fread(fid, MarkerLength, 'char')'));
                    end
                    else
                        nexFile.markers(markerCount,1).values{i,1}.numericValues = fread(fid, [n 1], 'uint32');
                    end
                end
                
                %added bonus data for ease of re-writing
                nexFile.markers(markerCount,1).type = type;
                nexFile.markers(markerCount,1).varVersion = varVersion;
                nexFile.markers(markerCount,1).FilePosDataOffset = offset;
                nexFile.markers(markerCount,1).nEvents = n;
                nexFile.markers(markerCount,1).tsDataType = tsDataType;
                nexFile.markers(markerCount,1).contDataType = contDataType;
                nexFile.markers(markerCount,1).contFragStartDataType = contFragmentStartDataType;
                nexFile.markers(markerCount,1).markerDataType = markerDataType;
                nexFile.markers(markerCount,1).Nex5Units = units;
                %nexFile.markers(markerCount,1).WireNumber = WireNumber;
                %nexFile.markers(markerCount,1).UnitNumber = UnitNumber;
                %nexFile.markers(markerCount,1).Gain = Gain;
                %nexFile.markers(markerCount,1).Filter = Filter;
                %nexFile.markers(markerCount,1).XPos = XPos;
                %nexFile.markers(markerCount,1).YPos = YPos;
                nexFile.markers(markerCount,1).Hz = WFrequency;
                nexFile.markers(markerCount,1).ADtoMV = ADtoMV;
                nexFile.markers(markerCount,1).NPointsWave = NPointsWave;
                nexFile.markers(markerCount,1).NMarkers = NMarkers;
                nexFile.markers(markerCount,1).MarkerLength = MarkerLength;
                nexFile.markers(markerCount,1).MVOfffset = MVOfffset;
                nexFile.markers(markerCount,1).PrethresholdTime = PrethresholdTime;
                
            otherwise
                disp (['unknown variable type ' num2str(type)]);
        end
    end %read Type
    % return to file position that was after reading the variable header
    fseek(fid, filePosition, 'bof');
    dummy = fread(fid, 60, 'char');
    if opts.progress; waitbar(i/nexFile.nChannels); end
end

% read and process metadata at the end of the file
try
    fseek(fid, 0,'eof');
    filelength = ftell(fid);
    if ( metaOffset > 0 && metaOffset < filelength )
        fseek(fid, metaOffset, 'bof');
        jsonMeta = fread(fid, filelength - metaOffset, '*char')';
        jsonMeta(end+1) = 0;
        jsonMeta = jsonMeta(1:min(find(jsonMeta==0))-1);  
        nexFile.metadata = jsonMeta;
        % disp(jsonMeta);
        meta = parse_json(nexFile.metadata);
        meta = meta{1};
        for i=1:length(meta.variables)
            varMeta = meta.variables{i};
            name = varMeta.name;
            if isfield(nexFile, 'neurons')
                for j=1:length(nexFile.neurons)
                    nrName = nexFile.neurons{j}.name;
                    if strcmp(nrName,name) == 1
                        if isfield(varMeta, 'unitNumber')
                            nexFile.neurons{j}.unitNumber = varMeta.unitNumber;
                        end
                        
                        if isfield(varMeta, 'probe')
                            if isfield(varMeta.probe, 'wireNumber')
                                nexFile.neurons{j}.wireNumber = varMeta.probe.wireNumber;
                            end
                            if isfield(varMeta.probe, 'position')
                                nexFile.neurons{j}.xPos = varMeta.probe.position.x;
                                nexFile.neurons{j}.yPos = varMeta.probe.position.y;
                            end
                        end                       
                        break
                    end
                end 
            end
            if isfield(nexFile, 'waves')
                for j=1:length(nexFile.waves)
                    waveName = nexFile.waves{j}.name;
                    if strcmp(waveName,name) == 1
                        if isfield(varMeta, 'unitNumber')
                            nexFile.waves{j}.unitNumber = varMeta.unitNumber;
                        end
                        if isfield(varMeta, 'probe')
                            if isfield(varMeta.probe, 'wireNumber')
                                nexFile.waves{j}.wireNumber = varMeta.probe.wireNumber;
                            end
                        end
                        break
                    end
                end  
            end
        end
    end
catch ME
    msgText = getReport(ME);
    warning('unable to process metadata')
    warning(msgText)
end

if opts.progress; waitbar(1); end
fclose(fid);
if opts.progress
    close(hWaitBar);
end

%update Data
nexFile.nChannels = length(nexFile.Channel); %cheap but works for now...

status = true;