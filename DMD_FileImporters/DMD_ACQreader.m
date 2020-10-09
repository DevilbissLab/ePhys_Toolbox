function [DataStruct, status, msg] = NSB_ACQreader(filepath,SubjectID,options)
% Wrapper to read files and assemble if necessarry
%BIOPAC's AcqKnowledge file
%https://www.biopac.com/wp-content/uploads/app156.pdf
%https://www.biopac.com/wp-content/uploads/app155.pdf
%
%
% Input file or directory
% combine files in the same directory
% uses A finite convention where there is a Group#2 ID#7002 TSoffset#210
% for now this gets pointed to a directory and load all the files

status = false; msg = '';
DataStruct = [];
switch nargin
    case 0
        [filename,filepath] = uigetfile({'*.acq','Biopac AcqKnowledge Data Format (*.acq)';},'Select a Biopac file...');
        filepath = fullfile(filepath,filename);
        options.logfile = '';
        options.chans = [];
        options.progress = true;
        filepathType = 2;
    case 1
        %is this a dir or file
        filepathType = exist(filepath);
        SubjectID = [];
        options.logfile = '';
        options.chans = [];
        options.progress = true;
        
        %set default options
        %log file
        %chan read vector
        %progress Bar
    case 2
        %is this a dir or file
        filepathType = exist(filepath);
        %if filepath is a file then ignore SubjectID
        options.logfile = '';
        options.chans = [];
        options.progress = true;
    case 3
        filepathType = exist(filepath);
        %check otptions
end

%filepathType = exist(filepath);
if filepathType == 2
    %This is a file - Pass through
    [DataStruct, status, msg] = NSB_ACQreadFile(filepath,options);
elseif filepathType == 7
    dirList = fuf(fullfile(filepath,'*.acq'));
    %        regexp(dirList,'(Group#\S*)(ID#\S*)(TSoffset#\S*)','ignorecase','match')
    %        tags = regexp(dirList,'(Group#\S*)[^a-zA-Z0-9]*(ID#\S*)[^a-zA-Z0-9]*(TSoffset#\S*)','ignorecase','tokens');
    tags = regexp(dirList,'(Group#)(\S*)[^a-zA-Z0-9]*(ID#)(\S*)[^a-zA-Z0-9]*(TSoffset#)(\S*)','ignorecase','tokens');
    for curTag = 1:length(tags)
        try, [group{curTag}, ID{curTag}, TSoffset{curTag}] = deal(tags{curTag}{1}{2:2:6}); end
    end
    
    TSoffset = cellfun(@str2double,TSoffset);
    uGroups = unique(group);
    uIDs = unique(ID);
    
    for curGroup = 1:length(uGroups)
        for curID = 1:length(uIDs)
            gIDX = strcmp(group,uGroups(curGroup));
            idIDX = strcmp(ID,uIDs(curID));
            IDX = gIDX & idIDX;
            if nnz(IDX) == 0
                continue;
            end
            realIDX = find(IDX);
            [~,sortIDX] = sort(TSoffset(IDX));
            
            sortFileNameList = dirList(IDX);
            sortFileNameList = sortFileNameList(sortIDX);
            
            for curFile = 1:length(sortFileNameList)
                [partialDataStruct, status, msg] = NSB_ACQreadFile(fullfile(filepath,sortFileNameList{curFile}),options);
                
                startVec = datevec(partialDataStruct.StartDate);
                FileOffset = TSoffset(realIDX(sortIDX(curFile)));
                if FileOffset == -1
                    %set a dose time @ end of file
                    partialDataStruct.EndDate = datenum([startVec(1:5),startVec(6)+partialDataStruct.nSeconds]);
                    partialDataStruct.doseTime = partialDataStruct.EndDate;
                    partialDataStruct.SubjectID = uIDs{curID};
                    DataStruct = partialDataStruct;
                    errorstr = ['Information: NSB_ACQreader >> Computed Dosing Time: ',datestr(DataStruct.doseTime)];
                    if ~isempty(options.logfile)
                        NSBlog(options.logfile,errorstr);
                    else
                        disp(errorstr);
                    end
                else
                    if isempty(DataStruct)
                        % set dose time at "0" i.e. offset before the
                        % file starts
                        partialDataStruct.EndDate = datenum([startVec(1:5),startVec(6)+partialDataStruct.nSeconds]);
                        partialDataStruct.doseTime = datenum([startVec(1:4),startVec(5)-FileOffset,startVec(6)]);
                        partialDataStruct.SubjectID = uIDs{curID};
                        DataStruct = partialDataStruct;
                        errorstr = ['Information: NSB_ACQreader >> Computed Dosing Time: ',datestr(DataStruct.doseTime)];
                        if ~isempty(options.logfile)
                            NSBlog(options.logfile,errorstr);
                        else
                            disp(errorstr);
                        end
                    else
                        %DataStruct.StartDate == 0 if no time could be found
                        if partialDataStruct.StartDate == 0
                            partialDataStruct.StartDate = datenum([0 0 0 0 FileOffset 0]);
                            partialDataStruct.StartDate = partialDataStruct.StartDate+DataStruct.StartDate;
                        elseif DataStruct.StartDate == 0 && partialDataStruct.StartDate ~= 0
                            %the 1st file we couldn't extract a time stamp,
                            %but now we can so there is a HUGE gap between
                            %recordings.
                            %move the 1st recording forward in time and
                            %reset dose time
                            DataStruct.StartDate = partialDataStruct.StartDate - datenum([0 0 0 0 FileOffset 0]);
                            startVec = datevec(DataStruct.StartDate);
                            DataStruct.EndDate = datenum([startVec(1:5),startVec(6)+DataStruct.nSeconds]);
                            DataStruct.doseTime = DataStruct.EndDate;
                            errorstr = ['Information: NSB_ACQreader >> Updated Dosing Time: ',datestr(DataStruct.doseTime)];
                            if ~isempty(options.logfile)
                                NSBlog(options.logfile,errorstr);
                            else
                                disp(errorstr);
                            end
                        end
                        for curChan = 1:partialDataStruct.nChannels
                            % check channels are the same
                            if strcmp(partialDataStruct.Channel(curChan).Name,DataStruct.Channel(curChan).Name)
                                
                                bufferTime = etime(datevec(partialDataStruct.StartDate), datevec(DataStruct.EndDate));
                                buffer = floor(bufferTime * partialDataStruct.Channel.Hz);
                                DataStruct.Channel(curChan).Data = [DataStruct.Channel(curChan).Data; zeros(buffer,1); partialDataStruct.Channel(curChan).Data ];
                                
                                %update
                                DataStruct.Channel.nSamples = DataStruct.Channel.nSamples + buffer + partialDataStruct.Channel.nSamples;
                                
                            else
                                %throw error
                            end
                        end
                        %update file level
                        nsamples = DataStruct.Channel(:).nSamples;
                        chanMax = find(max(DataStruct.Channel(:).nSamples),nsamples);
                        DataStruct.nSeconds = DataStruct.Channel(chanMax).nSamples/DataStruct.Channel(chanMax).Hz;
                        startVec = datevec(DataStruct.StartDate);
                        DataStruct.EndDate = datenum([startVec(1:5),startVec(6)+DataStruct.nSeconds]);
                    end
                end
            end
        end
    end
%DataStruct.FileName = fullfile(filepath,sortFileNameList{curFile});
if DataStruct.StartDate == 0
    %excel cannot handle a 0/0/000 date, so force to 1/1/1900
    DataStruct.StartDate = DataStruct.StartDate + datenum([2000 1 1 0 0 0]);
    DataStruct.EndDate = DataStruct.EndDate + datenum([2000 1 1 0 0 0]);
    DataStruct.doseTime = DataStruct.doseTime + datenum([2000 1 1 0 0 0]);
end

else
    errorstr = ['ERROR: NSB_ACQreader >> File does not exist: ',filepath];
    if ~isempty(options.logfile)
        status = NSBlog(options.logfile,errorstr);
    else
        msg = errorstr;
    end
end


status = true;

