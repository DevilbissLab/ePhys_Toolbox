function [plxFile, status] = DMD_PLXreader(fileName, readType, opts)

%right now read by type... try read by chan!!
%https://www.sensorsone.com/bit-to-measurement-resolution-converter/#fs
%MAP systems used a 12 bit DAC has 4095 steps There is a +/-1 mV input space
%so to return to ADC values divide mV by 0.000488400488400488 (i.e. 2/4095)

%Omniplex uses 16 bit DAC has 65535 steps
% 0.0000305180437934


plxFile = [];
status = false;

if ~ispc
    error('DMD_PLXreader requires mex-file compled for windows');
    return;
end

switch nargin
    case 0
        [fname, pathname] = uigetfile( {'*.plx';'.pl5'}, 'Select a Plexon file');
        fileName = strcat(pathname, fname);
        [~, ~, fext] = fileparts(fileName); %identify Nex Type
        readType = 0:6;
        opts.progress = true;
    case 1
        if isempty(fileName)
            [fname, pathname] = uigetfile( {'*.plx';'.pl5'}, 'Select a Plexon file');
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
        if isempty(readType)
            readType = 0:6;
        end
    case 3
        [pathname, fname, fext] = fileparts(fileName);
        fname = [fname,fext];
        if ~isfield(opts,'progress')
            opts.progress = true;
        end
        if isempty(readType)
            readType = 0:6;
        end
end
[ ~, isPl2 ] = internalPL2ResolveFilenamePlx( fileName );

if opts.progress
    warning off; %may be tex issues with underscores
    hWaitBar = waitbar(0, ['Please Wait, Opening: ',regexprep(fname,'[_^]',' ')]);
    warning on;
end

%read Header information
[plxFile.FileName,...
    plxFile.Version,...
    plxFile.Hz,...
    plxFile.Comment,...
    info.Trodalness, info.NPW, info.PrethresholdTime, info.SpikePeakV, info.SpikeADResBits, info.SlowPeakV, info.SlowADResBits,...
    plxFile.nSeconds,...
    plxFile.StartDate] = plx_information(fileName);
plxFile.StartDate = datenum(plxFile.StartDate);

[info.tscounts, info.wfcounts, info.evcounts, info.slowcounts] = plx_info(fileName,1);
info.tscounts(:,1) = []; % Note that for tscounts, wfcounts, the unit,channel indices i,j are off by one.
info.wfcounts(:,1) = []; % Note that for tscounts, wfcounts, the unit,channel indices i,j are off by one.

SpikeChannels = find(sum(info.tscounts));   %plexon stores this as an array. to determine which are recorded channels, find wires that have spike counts on any of the units (a-d and i)
EventChannels = find(info.evcounts);
ContChannels = [];                                      %Do not trust - old plx files do not report this

%What types of data do we have and add structures

neuronCount = 0;
eventCount = 0;
intervalCount = 0;
waveCount = 0;
popCount = 0;
contCount = 0;
markerCount = 0;

channelCount = 0;

Units = 'mV';


for type = readType
    if ismember(type, readType)
        switch type
            case 0 % neuron
                [n, plx.ChanNames] = plx_chan_names(fileName);
                [n, plx.ChanIDs] = plx_chanmap(fileName);
                [n, plx.ChanGains] = plx_chan_gains(fileName);
                [n, plx.ChanFilters] = plx_chan_filters(fileName); % 0 or 1 array
                
                nUnits = size(info.tscounts,1);
                nNeurons = nnz(info.tscounts);
                if opts.progress
                    warning off; %may be tex issues with underscores
                    waitbar(0, hWaitBar, ['Reading Neuron Data: ',regexprep(fname,'[_^]',' ')]);
                    warning on;
                end
                
                for curWire = SpikeChannels
                    for curUnit = 1:nUnits
                        if opts.progress; waitbar(neuronCount / nNeurons); end
                        if info.tscounts(curUnit, curWire) > 0
                            neuronCount = neuronCount+1;
                            channelCount = channelCount+1;
                            if curUnit == 1
                                name = [deblank(plx.ChanNames(curWire,:)), char(105)];
                            else
                                name = [deblank(plx.ChanNames(curWire,:)), char(97+curUnit-2)];
                            end
                            plxFile.neurons(neuronCount,1).Name = name;
                            plxFile.neurons(neuronCount,1).ChNumber = channelCount;
                            plxFile.neurons(neuronCount,1).Units = '';                         % No units to a spike train
                            [nTimestamps, plxFile.neurons(neuronCount,1).ts] = plx_ts(fileName, curWire, curUnit-1); %NOTE: Plexon is 0 indexed. we updated this for wire not unit above
                            
                            %added bonus data for ease of re-writing
                            %if Nex ver is <=100 Wire and Unit Number = 0
                            plxFile.neurons(neuronCount,1).type = 0;
                            plxFile.neurons(neuronCount,1).varVersion = 100;
                            plxFile.neurons(neuronCount,1).FilePosDataOffset = [];
                            plxFile.neurons(neuronCount,1).nEvents = nTimestamps;
                            plxFile.neurons(neuronCount,1).WireNumber = curWire;
                            plxFile.neurons(neuronCount,1).UnitNumber = curUnit;
                            plxFile.neurons(neuronCount,1).Gain = plx.ChanGains(curWire);
                            plxFile.neurons(neuronCount,1).Filter = plx.ChanFilters(curWire);
                            plxFile.neurons(neuronCount,1).XPos = 0;                                    %This is calculated in Nex as neuron position in a matrix
                            plxFile.neurons(neuronCount,1).YPos = 0;                                    %This is calculated in Nex as neuron position in a matrix
                            plxFile.neurons(neuronCount,1).Hz = 0;
                            plxFile.neurons(neuronCount,1).ADtoMV = 0;
                            plxFile.neurons(neuronCount,1).NPointsWave = 0;
                            plxFile.neurons(neuronCount,1).NMarkers = 0;
                            plxFile.neurons(neuronCount,1).MarkerLength = 0;
                            plxFile.neurons(neuronCount,1).MVOfffset = 0;
                        end
                    end
                end
                
            case 1 % event
                [n, plx.ChanNames] = plx_event_names(fileName);
                [n, plx.ChanIDs] = plx_event_chanmap(fileName);
                %EventChannels = plx.ChanIDs(EventChannels);
                nEvents = length(EventChannels);
                 if opts.progress
                    warning off; %may be tex issues with underscores
                    waitbar(0, hWaitBar, ['Reading Event Data: ',regexprep(fname,'[_^]',' ')]);
                    warning on;
                end
                
                for curChan = 1:length(EventChannels)
                    eventCount = eventCount+1;
                    channelCount = channelCount+1;
                    if opts.progress; waitbar(eventCount / nEvents); end
                    
                    plxFile.events(eventCount,1).Name = deblank(plx.ChanNames(EventChannels(curChan),:));
                    plxFile.events(eventCount,1).ChNumber = channelCount;
                    plxFile.events(eventCount,1).Units = '';
                    
                    [nTimestamps, plxFile.events(eventCount,1).ts, StrobedEvents] = plx_event_ts(fileName, plx.ChanIDs(EventChannels(curChan)));
                    
                    
                    %added bonus data for ease of re-writing
                    %if Nex ver is <=100 Wire and Unit Number = 0
                    plxFile.events(eventCount,1).type = 1;
                    plxFile.events(eventCount,1).varVersion = 100;
                    plxFile.events(eventCount,1).FilePosDataOffset = [];
                    plxFile.events(eventCount,1).nEvents = nTimestamps;
                    plxFile.events(eventCount,1).WireNumber = [];
                    plxFile.events(eventCount,1).UnitNumber = [];
                    plxFile.events(eventCount,1).Gain = [];
                    plxFile.events(eventCount,1).Filter = [];
                    plxFile.events(eventCount,1).XPos = [];                                    %This is calculated in Nex as neuron position in a matrix
                    plxFile.events(eventCount,1).YPos = [];                                    %This is calculated in Nex as neuron position in a matrix
                    plxFile.events(eventCount,1).Hz = [];
                    plxFile.events(eventCount,1).ADtoMV = [];
                    plxFile.events(eventCount,1).NPointsWave = [];
                    plxFile.events(eventCount,1).NMarkers = [];
                    plxFile.events(eventCount,1).MarkerLength = [];
                    plxFile.events(eventCount,1).MVOfffset = [];
                end
                
            case 2 % interval
                %unclear whether this is used in plx files
                disp (['Interval not Implemented in .plx Importer']);
            case 3 % waveform
                
                % To Do
                disp (['Waveform not Implemented in .plx Importer']);
                
            case 4 % population vector
                %unclear whether this is used in plx files
                disp (['Population Vector not Implemented in .plx Importer']);
            case 5 % continuous variable
                [n, plx.ChanIDs] = plx_ad_chanmap(fileName);
                [n, plx.ChanNames] = plx_adchan_names(fileName);
                [n, plx.ChanGains] = plx_adchan_gains(fileName);
                [n, plx.ChanSamples] = plx_adchan_samplecounts(fileName);
                
                ContChannels = plx.ChanIDs( find( plx.ChanSamples));
                nContChans = length(ContChannels);
                 if opts.progress
                    warning off; %may be tex issues with underscores
                    waitbar(0, hWaitBar, ['Reading Continuous Data: ',regexprep(fname,'[_^]',' ')]);
                    warning on;
                 end
                
                for curChan = 1:nContChans
                    contCount = contCount+1;
                    channelCount = channelCount+1;
                     if opts.progress; waitbar(contCount / nContChans); end
                    
                    plxFile.Channel(contCount,1).Name = deblank(plx.ChanNames(curChan,:));
                    plxFile.Channel(contCount,1).ChNumber = channelCount;
                    plxFile.Channel(contCount,1).Units = Units;
                    
                    %read channel data
                    if ~isPl2
                    [plxFile.Channel(contCount,1).Hz,...
                        plxFile.Channel(contCount,1).nSamples,...
                        plxFile.Channel(contCount,1).timestamps,...
                        plxFile.Channel(contCount,1).fragmentStarts,...
                        plxFile.Channel(contCount,1).Data] = plx_ad_v(fileName, plx.ChanIDs(curChan));
                    else
                        pl2ad = PL2Ad(fileName, ContChannels(curChan +1));
                        plxFile.Channel(contCount,1).Hz = pl2ad.ADFreq;
                        plxFile.Channel(contCount,1).nSamples = length(pl2ad.Values);
                        plxFile.Channel(contCount,1).timestamps = pl2ad.FragTs;
                        plxFile.Channel(contCount,1).fragmentStarts = pl2ad.FragCounts;
                        plxFile.Channel(contCount,1).Data = pl2ad.Values;
                        clear pl2ad;
                    end
%                     [plxFile.Channel(contCount,1).Hz,...
%                         plxFile.Channel(contCount,1).nSamples,...
%                         plxFile.Channel(contCount,1).timestamps,...
%                         plxFile.Channel(contCount,1).fragmentStarts,...
%                         plxFile.Channel(contCount,1).Data] = plx_ad(fileName, plx.ChanIDs(curChan)); %Debug ONLY read raw ADC values
                    
                    % .fragmentStarts - array of start indexes for fragments in contvar.data array
                    plxFile.Channel(contCount,1).fragmentStarts = plxFile.Channel(contCount,1).fragmentStarts - ( [plxFile.Channel(contCount,1).fragmentStarts(1),diff(plxFile.Channel(contCount,1).fragmentStarts)]-1 );
                    
                    %added bonus data for ease of re-writing
                    plxFile.Channel(contCount,1).type = 5;                                           %Nex Var Type
                    plxFile.Channel(contCount,1).varVersion = 100;                         %Nex Var Version
                    plxFile.Channel(contCount,1).FilePosDataOffset = [];
                    plxFile.Channel(contCount,1).nEvents = length(plxFile.Channel(contCount,1).timestamps);
                    plxFile.Channel(contCount,1).WireNumber = plx.ChanIDs(curChan);
                    plxFile.Channel(contCount,1).UnitNumber = [];
                    plxFile.Channel(contCount,1).Gain = plx.ChanGains(curChan);
                    plxFile.Channel(contCount,1).Filter = [];
                    plxFile.Channel(contCount,1).XPos = [];
                    plxFile.Channel(contCount,1).YPos = [];
                    plxFile.Channel(contCount,1).Hz = plxFile.Channel(contCount,1).Hz;
                    plxFile.Channel(contCount,1).ADtoMV = [];                                     %none for plx. for pl2 see plx_ad.m
                    plxFile.Channel(contCount,1).NPointsWave = plxFile.Channel(contCount,1).nSamples;
                    plxFile.Channel(contCount,1).NMarkers = [];
                    plxFile.Channel(contCount,1).MarkerLength = [];
                    plxFile.Channel(contCount,1).MVOfffset = [];
                    plxFile.Channel(contCount,1).PrethresholdTime = info.PrethresholdTime;
                end
                
            case 6 % marker
                %unclear whether this is used in plx files
                disp (['Marker not Implemented in .plx Importer']);
            otherwise
                disp (['unknown variable type ' num2str(type)]);
        end
    end %read Type
    
end
if opts.progress; waitbar(1); end

if opts.progress
    close(hWaitBar);
end

%update Data
plxFile.nChannels = channelCount;
plx_close(fileName);
status = true;


