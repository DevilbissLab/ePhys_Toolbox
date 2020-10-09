function [DataStruct, status, msg] = NSB_ACQreadFile(filename,options)
%
%BIOPAC's AcqKnowledge file
%https://www.biopac.com/wp-content/uploads/app156.pdf
%https://www.biopac.com/wp-content/uploads/app155.pdf


status = false; msg = '';
switch nargin
    case 0
        [filename,filepath] = uigetfile({'*.acq','Biopac AcqKnowledge Data Format (*.acq)';},'Select a Biopac file...');
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
    errorstr = ['ERROR: NSB_ACQreader >> File does not exist: ',filename];
    if ~isempty(options.logfile)
        status = NSBlog(options.logfile,errorstr);
    else
        msg = errorstr;
    end
    return;
end

%Read ACQ
acq = load_acq(filename);

%Translate Structure
DataStruct.Version = acq.hdr.graph.file_version;
switch DataStruct.Version
    case 30
        DataStruct.VersionName = 'Pre-version 2.0';
    case 31
        DataStruct.VersionName = 'Version 2.0 Beta 1';
    case 32
        DataStruct.VersionName = 'Version 2.0';
    case 33
        DataStruct.VersionName = 'Version 2.0.7 (Mac)';
    case 34
        DataStruct.VersionName = 'VVersion 3.0 In-house Release 1';
    case 35
        DataStruct.VersionName = 'Version 3.03';
    case 36
        DataStruct.VersionName = 'Version 3.5x (Win 95, 98, NT)';
    case 37
        DataStruct.VersionName = 'Version of BSL/PRO 3.6.x';
    case 38
        DataStruct.VersionName = 'Version of Acq 3.7.0-3.7.2 (Win 98, 98SE, NT, Me, 2000)';
    case 39
        DataStruct.VersionName = 'Version of Acq 3.7.3 or above (Win 98, 98SE, 2000, Me, XP)';
    case 41
        DataStruct.VersionName = 'Version of Acq 3.8.1 or above (Win 98, 98SE, 2000, Me, XP)';
    case 42
        DataStruct.VersionName = 'Version of BSL/PRO 3.7.X or above (Win 98, 98SE, 2000, Me, XP)';
    case 43
        DataStruct.VersionName = 'Version of Acq 3.8.2 or above (Win 98, 98SE, 2000, Me, XP)';
    case 44
        DataStruct.VersionName = 'Version of BSL/PRO 3.8.x or above';
    case 45
        DataStruct.VersionName = 'Version of Acq 3.9.0 or above';
    otherwise
        DataStruct.VersionName = 'Version Unknown';
end
DataStruct.SubjectID = '';
DataStruct.Comment = '';
DataStruct.Technician = '';
DataStruct.StartDate = datenum([0 0 0 0 0 0]); %acq Does not store real time
DataStruct.FileFormat = '.acq';
DataStruct.nSeconds = size(acq.data,1)/acq.hdr.graph.sample_time/1000;
DataStruct.nChannels = acq.hdr.graph.num_channels;
DataStruct.Hz = 1000/acq.hdr.graph.sample_time;
DataStruct.FileName = filename;

%For each channel
for curChan = 1:DataStruct.nChannels
    
    DataStruct.Channel(curChan).Name = acq.hdr.per_chan_data(curChan).comment_text;
    DataStruct.Channel(curChan).ChNumber = acq.hdr.per_chan_data(curChan).num;
    DataStruct.Channel(curChan).Units = acq.hdr.per_chan_data(curChan).units_text;
    DataStruct.Channel(curChan).nSamples = acq.hdr.per_chan_data(curChan).buf_length;
    DataStruct.Channel(curChan).Hz = DataStruct.Hz/acq.hdr.per_chan_data(curChan).var_sample_divider; %channel sample rate can be a freaction of glogal samople rate
    DataStruct.Channel(curChan).Data = acq.data(:,curChan);
    
end

%add marker channel
%If there is a marker channel then you can extract actual times
if acq.markers.lMarkers > 0
    for curMarker = 1:length(acq.markers.szText)
        dStr = regexp(acq.markers.szText{curMarker},'\d*:\d*:\d*\s*AM|\d*:\d*:\d*\s*PM','match');
        if ~isempty(dStr)
            markerTS = double(acq.markers.lSample(curMarker))/DataStruct.Hz;
            dVec = datevec(dStr);
            dVec = [dVec(1:5), dVec(6)-markerTS];
            
            DataStruct.StartDate = datenum(dVec); %acq Does not store real time
        else
        end
    end
end
%Add markers here.

% %Write EDF+
% options.logfile = '';
%         options.chans = [];
%         options.progress = true;
% [status] = NSB_EDFplusWriter(DataStruct, filename, options);

status = true;

