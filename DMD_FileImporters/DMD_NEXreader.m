function [nexFile, status] = NSB_NEXreader(fileName,readType)
% [nexfile] = fullreadNexFile(fileName) -- read .nex file and return file data
% in nexfile structure
%
% INPUT:
%   fileName - if empty string, will use File Open dialog
%   readType     - vector of data filetypes, if empty will read all types
%
% OUTPUT:
%   nexFile - a structure containing .nex file data
%   nexFile.version - file version
%   nexFile.comment - file comment
%   nexFile.tbeg - beginning of recording session (in seconds)
%   nexFile.teng - end of resording session (in seconds)
%
%   nexFile.neurons - array of neuron structures
%           neuron.Name - name of a neuron variable
%           neuron.ts - array of neuron timestamps (in seconds)
%               to access timestamps for neuron 2 use {n} notation:
%               nexFile.neurons{2}.ts
%
%   nexFile.events - array of event structures
%           event.Name - name of neuron variable
%           event.ts - array of event timestamps (in seconds)
%               to access timestamps for event 3 use {n} notation:
%               nexFile.events{3}.ts
%
%   nexFile.intervals - array of interval structures
%           interval.Name - name of neuron variable
%           interval.intStarts - array of interval starts (in seconds)
%           interval.intEnds - array of interval ends (in seconds)
%
%   nexFile.waves - array of wave structures
%           wave.Name - name of neuron variable
%           wave.NPointsWave - number of data points in each wave
%           wave.WFrequency - A/D frequency for wave data points
%           wave.ts - array of wave timestamps (in seconds)
%           wave.waveforms - matrix of waveforms (in milliVolts), each
%                             waveform is a vector
%
%   nexFile.Channel - array of contvar structures
%           contvar.Name - name of neuron variable
%           contvar.ADFrequency - A/D frequency for data points
%
%           continuous (a/d) data come in fragments. Each fragment has a timestamp
%           and an index of the a/d data points in data array. The timestamp corresponds to
%           the time of recording of the first a/d value in this fragment.
%
%           contvar.ts - array of timestamps (fragments start times in seconds)
%           contvar.fragmentStarts - array of start indexes for fragments in contvar.data array
%           contvar.data - array of data points (in milliVolts)
%
%   nexFile.popvectors - array of popvector (population vector) structures
%           popvector.Name - name of popvector variable
%           popvector.weights - array of population vector weights
%
%   nexFile.markers - array of marker structures
%           marker.Name - name of marker variable
%           marker.ts - array of marker timestamps (in seconds)
%           marker.values - array of marker value structures
%           	marker.value.Name - name of marker value
%           	marker.value.strings - array of marker value strings
%
% This file was originally written by Nex Technologies and likely copyrighted.
% See http://www.neuroexplorer.com/code.html but no licence was Identified
% Modified by David M. Devilbiss (26Jan2009) for Full Read of Data
% release version 1.0 10Oct2010
% added ability to import data type subset
% 2013Jul20 Ver 1.1 Added .channel.ChNumber

nexFile = [];
status = false;
if (nargin < 1 | length(fileName) == 0)
    [fname, pathname] = uigetfile('*.nex', 'Select a NeuroExplorer file');
    fileName = strcat(pathname, fname);
    readType = 0:6;
elseif nargin == 1
    [pathname, fname, fext] = fileparts(fileName);
    fname = [fname,fext];
    readType = 0:6;
else
    [pathname, fname, fext] = fileparts(fileName);
    fname = [fname,fext];
end

fid = fopen(fileName, 'r');
if(fid == -1)
    error 'Unable to open file'
    return
end

warning off; %may be tex issues with underscores
hWaitBar = waitbar(0, ['Please Wait, Opening: ',regexprep(fname,'[_^]',' ')]);
warning on;

magic = fread(fid, 1, 'int32');
if magic ~= 827868494
    error 'The file is not a valid .nex file'
end
nexFile.Version = fread(fid, 1, 'int32');
nexFile.SubjectID = '';
nexFile.Comment = deblank(char(fread(fid, 256, 'char')'));
nexFile.StartDate = [];
nexFile.FileFormat = '.nex';
nexFile.Hz = fread(fid, 1, 'double');
tbeg = fread(fid, 1, 'int32')./nexFile.Hz;
tend = fread(fid, 1, 'int32')./nexFile.Hz;
FileInfo = dir(fileName);
nexFile.StartDate = datenum([0 0 0 0 0 tbeg]); %Nex Does not store real time
nexFile.nSeconds = tend - tbeg;
nexFile.nChannels = fread(fid, 1, 'int32');

% skip location of next header and padding
fseek(fid, 260, 'cof');

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
    offset = fread(fid, 1, 'int32');
    n = fread(fid, 1, 'int32');
    WireNumber = fread(fid, 1, 'int32');
    UnitNumber = fread(fid, 1, 'int32');
    Gain = fread(fid, 1, 'int32');
    Filter = fread(fid, 1, 'int32');
    XPos = fread(fid, 1, 'double');
    YPos = fread(fid, 1, 'double');
    WFrequency = fread(fid, 1, 'double'); % wf sampling fr.
    ADtoMV  = fread(fid, 1, 'double'); % coeff to convert from AD values to Millivolts.
    NPointsWave = fread(fid, 1, 'int32'); % number of points in each wave
    NMarkers = fread(fid, 1, 'int32'); % how many values are associated with each marker
    MarkerLength = fread(fid, 1, 'int32'); % how many characters are in each marker value
    MVOfffset = fread(fid, 1, 'double'); % coeff to shift AD values in Millivolts: mv = raw*ADtoMV+MVOfffset
    Units = 'mV';
    %60 char pad delt with below
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
                nexFile.neurons(neuronCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                fseek(fid, filePosition, 'bof');
                
                %added bonus data for ease of re-writing
                nexFile.neurons(neuronCount,1).type = type;
                nexFile.neurons(neuronCount,1).varVersion = varVersion;
                nexFile.neurons(neuronCount,1).FilePosDataOffset = offset;
                nexFile.neurons(neuronCount,1).nEvents = n;
                nexFile.neurons(neuronCount,1).WireNumber = WireNumber;
                nexFile.neurons(neuronCount,1).UnitNumber = UnitNumber;
                nexFile.neurons(neuronCount,1).Gain = Gain;
                nexFile.neurons(neuronCount,1).Filter = Filter;
                nexFile.neurons(neuronCount,1).XPos = XPos;
                nexFile.neurons(neuronCount,1).YPos = YPos;
                nexFile.neurons(neuronCount,1).Hz = WFrequency;
                nexFile.neurons(neuronCount,1).ADtoMV = ADtoMV;
                nexFile.neurons(neuronCount,1).NPointsWave = NPointsWave;
                nexFile.neurons(neuronCount,1).NMarkers = NMarkers;
                nexFile.neurons(neuronCount,1).MarkerLength = MarkerLength;
                nexFile.neurons(neuronCount,1).MVOfffset = MVOfffset;
                
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
                nexFile.events(eventCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                fseek(fid, filePosition, 'bof');
                
                %added bonus data for ease of re-writing
                nexFile.events(eventCount,1).type = type;
                nexFile.events(eventCount,1).varVersion = varVersion;
                nexFile.events(eventCount,1).FilePosDataOffset = offset;
                nexFile.events(eventCount,1).nEvents = n;
                nexFile.events(eventCount,1).WireNumber = WireNumber;
                nexFile.events(eventCount,1).UnitNumber = UnitNumber;
                nexFile.events(eventCount,1).Gain = Gain;
                nexFile.events(eventCount,1).Filter = Filter;
                nexFile.events(eventCount,1).XPos = XPos;
                nexFile.events(eventCount,1).YPos = YPos;
                nexFile.events(eventCount,1).Hz = WFrequency;
                nexFile.events(eventCount,1).ADtoMV = ADtoMV;
                nexFile.events(eventCount,1).NPointsWave = NPointsWave;
                nexFile.events(eventCount,1).NMarkers = NMarkers;
                nexFile.events(eventCount,1).MarkerLength = MarkerLength;
                nexFile.events(eventCount,1).MVOfffset = MVOfffset;
                
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
                nexFile.intervals(intervalCount,1).intStarts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                nexFile.intervals(intervalCount,1).intEnds = fread(fid, [n 1], 'int32')./nexFile.Hz;
                fseek(fid, filePosition, 'bof');
                
                %added bonus data for ease of re-writing
                nexFile.intervals(intervalCount,1).type = type;
                nexFile.intervals(intervalCount,1).varVersion = varVersion;
                nexFile.intervals(intervalCount,1).FilePosDataOffset = offset;
                nexFile.intervals(intervalCount,1).nEvents = n;
                nexFile.intervals(intervalCount,1).WireNumber = WireNumber;
                nexFile.intervals(intervalCount,1).UnitNumber = UnitNumber;
                nexFile.intervals(intervalCount,1).Gain = Gain;
                nexFile.intervals(intervalCount,1).Filter = Filter;
                nexFile.intervals(intervalCount,1).XPos = XPos;
                nexFile.intervals(intervalCount,1).YPos = YPos;
                nexFile.intervals(intervalCount,1).Hz = WFrequency;
                nexFile.intervals(intervalCount,1).ADtoMV = ADtoMV;
                nexFile.intervals(intervalCount,1).NPointsWave = NPointsWave;
                nexFile.intervals(intervalCount,1).NMarkers = NMarkers;
                nexFile.intervals(intervalCount,1).MarkerLength = MarkerLength;
                nexFile.intervals(intervalCount,1).MVOfffset = MVOfffset;
                
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
                
                fseek(fid, offset, 'bof');
                nexFile.waves(waveCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                nexFile.waves(waveCount,1).waveforms = fread(fid, [NPointsWave n], 'int16').*ADtoMV + MVOfffset;
                fseek(fid, filePosition, 'bof');
                
                %added bonus data for ease of re-writing
                nexFile.waves(waveCount,1).type = type;
                nexFile.waves(waveCount,1).varVersion = varVersion;
                nexFile.waves(waveCount,1).FilePosDataOffset = offset;
                nexFile.waves(waveCount,1).nEvents = n;
                nexFile.waves(waveCount,1).WireNumber = WireNumber;
                nexFile.waves(waveCount,1).UnitNumber = UnitNumber;
                nexFile.waves(waveCount,1).Gain = Gain;
                nexFile.waves(waveCount,1).Filter = Filter;
                nexFile.waves(waveCount,1).XPos = XPos;
                nexFile.waves(waveCount,1).YPos = YPos;
                %nexFile.waves(waveCount,1).WFrequency = WFrequency;
                nexFile.waves(waveCount,1).ADtoMV = ADtoMV;
                nexFile.waves(waveCount,1).NPointsWave = NPointsWave;
                nexFile.waves(waveCount,1).NMarkers = NMarkers;
                nexFile.waves(waveCount,1).MarkerLength = MarkerLength;
                nexFile.waves(waveCount,1).MVOfffset = MVOfffset;
                
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
                fseek(fid, filePosition, 'bof');
                
                %added bonus data for ease of re-writing
                nexFile.popvectors(popCount,1).type = type;
                nexFile.popvectors(popCount,1).varVersion = varVersion;
                nexFile.popvectors(popCount,1).FilePosDataOffset = offset;
                nexFile.popvectors(popCount,1).nEvents = n;
                nexFile.popvectors(popCount,1).WireNumber = WireNumber;
                nexFile.popvectors(popCount,1).UnitNumber = UnitNumber;
                nexFile.popvectors(popCount,1).Gain = Gain;
                nexFile.popvectors(popCount,1).Filter = Filter;
                nexFile.popvectors(popCount,1).XPos = XPos;
                nexFile.popvectors(popCount,1).YPos = YPos;
                nexFile.popvectors(popCount,1).Hz = WFrequency;
                nexFile.popvectors(popCount,1).ADtoMV = ADtoMV;
                nexFile.popvectors(popCount,1).NPointsWave = NPointsWave;
                nexFile.popvectors(popCount,1).NMarkers = NMarkers;
                nexFile.popvectors(popCount,1).MarkerLength = MarkerLength;
                nexFile.popvectors(popCount,1).MVOfffset = MVOfffset;
                
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
                fseek(fid, offset, 'bof');
                nexFile.Channel(contCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                nexFile.Channel(contCount,1).fragmentStarts = fread(fid, [n 1], 'int32') + 1;
                nexFile.Channel(contCount,1).Data = fread(fid, [NPointsWave 1], 'int16').*ADtoMV + MVOfffset;
                fseek(fid, filePosition, 'bof');
                
                %added bonus data for ease of re-writing
                nexFile.Channel(contCount,1).type = type;
                nexFile.Channel(contCount,1).varVersion = varVersion;
                nexFile.Channel(contCount,1).FilePosDataOffset = offset;
                nexFile.Channel(contCount,1).nEvents = n;
                nexFile.Channel(contCount,1).WireNumber = WireNumber;
                nexFile.Channel(contCount,1).UnitNumber = UnitNumber;
                nexFile.Channel(contCount,1).Gain = Gain;
                nexFile.Channel(contCount,1).Filter = Filter;
                nexFile.Channel(contCount,1).XPos = XPos;
                nexFile.Channel(contCount,1).YPos = YPos;
                %nexFile.Channel(contCount,1).WFrequency = WFrequency;
                nexFile.Channel(contCount,1).ADtoMV = ADtoMV;
                nexFile.Channel(contCount,1).NPointsWave = NPointsWave;
                nexFile.Channel(contCount,1).NMarkers = NMarkers;
                nexFile.Channel(contCount,1).MarkerLength = MarkerLength;
                nexFile.Channel(contCount,1).MVOfffset = MVOfffset;
                
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
                nexFile.markers(markerCount,1).ts = fread(fid, [n 1], 'int32')./nexFile.Hz;
                for i=1:NMarkers
                    nexFile.markers(markerCount,1).values{i,1}.Name = deblank(char(fread(fid, 64, 'char')'));
                    for p = 1:n
                        nexFile.markers(markerCount,1).values{i,1}.strings{p, 1} = deblank(char(fread(fid, MarkerLength, 'char')'));
                    end
                end
                fseek(fid, filePosition, 'bof');
                
                %added bonus data for ease of re-writing
                nexFile.markers(markerCount,1).type = type;
                nexFile.markers(markerCount,1).varVersion = varVersion;
                nexFile.markers(markerCount,1).FilePosDataOffset = offset;
                nexFile.markers(markerCount,1).nEvents = n;
                nexFile.markers(markerCount,1).WireNumber = WireNumber;
                nexFile.markers(markerCount,1).UnitNumber = UnitNumber;
                nexFile.markers(markerCount,1).Gain = Gain;
                nexFile.markers(markerCount,1).Filter = Filter;
                nexFile.markers(markerCount,1).XPos = XPos;
                nexFile.markers(markerCount,1).YPos = YPos;
                nexFile.markers(markerCount,1).Hz = WFrequency;
                nexFile.markers(markerCount,1).ADtoMV = ADtoMV;
                nexFile.markers(markerCount,1).NPointsWave = NPointsWave;
                nexFile.markers(markerCount,1).NMarkers = NMarkers;
                nexFile.markers(markerCount,1).MarkerLength = MarkerLength;
                nexFile.markers(markerCount,1).MVOfffset = MVOfffset;
                
            otherwise
                disp (['unknown variable type ' num2str(type)]);
        end
    end
    dummy = fread(fid, 60, 'char');
    waitbar(i/nexFile.nChannels);
end
waitbar(1);
fclose(fid);
close(hWaitBar)

%update Data
nexFile.nChannels = length(nexFile.Channel); %cheap but works for now...

status = true;