function [DataStruct, status] = DMD_DataImportModule(fileinfo,options)
%[status, DataStruct] = DMD_DataImportModule(fileinfo,options)
%
% File Types Read: EDF,EDF+,Nex,Nex5,Plx,Pl2,Spike2(SMR),acq
%
% Inputs:
%   fileinfo              - (Struct)                                                        Originates from StudyDesign cell(:,1)
%                               .type - file type (.edf,.rec,.nex,.smr, etc.)
%                               .path - file path
%                               .name - file name
%
%   options               - (Struct) 'dir','xls','xml'
%                               .progress - (logical) show progress bar
%                               .logfile - logfile path+name
%                               .chans - specify specific channels 
%                               .datatypes - limit read to specigic data
%                               types (Nex and Plx)
%                                              [] = all types
%                                              0 = 'neurons';.
%                                              1 =  'events';
%                                              2 =  'intervals';;
%                                              3 =   'waves';
%                                              4 =  'popvectors'
%                                              5 =  ''contvars';
%                                              6 =  ''markers';
%
% Outputs:
%   DataStruct           - (struct) DMD File DataStructure
%                           returns a single struct representing the file for that Subject (ID)
%   status               - (logical) return value
%
%
% Written By David M. Devilbiss
% Rowan University (ddevilbiss@gmail.com)
% 2018-2-28, Version 1.0 inspired by NSB code
%

%DMD File DataStructure:
%All fields are requisite. others can be added and are optional
% .Version
% .SubjectID
% .Comment
% .StartDate
% .FileFormat
% .nRecords
% .nSeconds
% .nChannels
% .Channel
%     .Name
%     .ChNumber
%     .Units
%     .nSamples
%     .Hz
%     .Data
% .FileName

status = false;

if nargin == 1
    options.logfile = '';
    options.chans = 'all';
    options.progress = true;
    options.datatypes = [];
end

try
switch lower(fileinfo.type)
        case {'.edf','.rec'}
            FileName = fullfile(fileinfo.path,fileinfo.name);
            if exist(FileName,'file') ~= 2
                FileName = fullfile(fileinfo.path,[fileinfo.name, fileinfo.type]);
                if exist(FileName,'file') ~= 2
                    status = false;
                    DataStruct = [];
                    return;
                end
            end
            
            if nargin == 2
                [DataStruct, status] = DMD_EDFreader2(FileName,options);
            else
                [DataStruct, status] = DMD_EDFreader2(FileName);
            end
            if status
                DataStruct.Filename = FileName; % < this is used by DMD_SaveSpectralData and other 'save' functions to put data in a NSBOutput subfolder
            end
            
        case {'.nex','.nex5'}
            FileName = fullfile(fileinfo.path,fileinfo.name);
            if exist(FileName,'file') ~= 2
                FileName = fullfile(fileinfo.path,[fileinfo.name, fileinfo.type]);
                if exist(FileName,'file') ~= 2
                    status = false;
                    DataStruct = [];
                    return;
                end
            end
            %Warning Does not produce .nSamples
             if isfield(options,'datatypes')
                 readType = options.datatypes;
             else
                 readType = [];
             end
             [DataStruct, status] = DMD_NEXreader(FileName, readType, options);
             %[DataStruct, status] = DMD_NEXreader(FileName,5); %Read only Continuous channels
             %Nex does not store creation date so try to extract from file system
             %see: https://www.mathworks.com/matlabcentral/answers/288339-how-to-get-creation-date-of-files
             warning('DMD_DataImportModule: Nex/Nex5 files do not store file start datetime. Using filesystem creation date');
             try
                 if ispc
                     date = System.IO.File.GetCreationTime(FileName);
                     DataStruct.StartDate = datenum(double([date.Year, date.Month, date.Day, date.Hour, date.Minute, date.Second]));
                 else
                     DataStruct.StartDate = datenum('01-01-01');
                 end
             catch
                 DataStruct.StartDate = datenum('01-01-01');
             end
             if status
                DataStruct.Filename = FileName;
            end
            
            case {'.plx','.pl2'}
            FileName = fullfile(fileinfo.path,fileinfo.name);
            if exist(FileName,'file') ~= 2
                FileName = fullfile(fileinfo.path,[fileinfo.name, fileinfo.type]);
                if exist(FileName,'file') ~= 2
                    status = false;
                    DataStruct = [];
                    return;
                end
            end
             if isfield(options,'datatypes')
                 readType = options.datatypes;
             else
                 readType = [];
             end
             %Warning Does not produce .nSamples
            [DataStruct, status] = DMD_PLXreader(FileName, readType, options);
            %[DataStruct, status] = DMD_NEXreader(FileName,5); %Read only Continuous channels
            if status
                DataStruct.Filename = FileName;
            end
            
        case {'.smr'}
            parms.dataset = fullfile(fileinfo.path,fileinfo.name);
            parms.DataChannels = 'ALL';
            parms.EventChannel = 'ALL';
            [DataStruct, status] = DMD_Spike2DataLoader(parms); %untested << incompatable structure
            if status
                DataStruct.Filename = fullfile(fileinfo.path,fileinfo.name);
            end
            
        case {'.acq'}
            FileName = fullfile(fileinfo.path,fileinfo.name);
            if exist(FileName) == 0
                FileName = fileinfo.path;
            end
            [DataStruct, status, msg] = DMD_ACQreader(FileName,fileinfo.name,options);
            if status
                DataStruct.Filename = FileName;
            end
            
        otherwise
            %add other importers here ....
            status = false;
            DataStruct = [];
            return;
end
[~,~,Ext] = fileparts(DataStruct.Filename);
if ~strcmp(DataStruct.Filename(end),'\') && isempty(Ext)
    DataStruct.Filename = [DataStruct.Filename,filesep];
end
catch ME
    errorstr = ['ERROR: DMD_DataImportModule >> ',ME.message];
    if ~isempty(ME.stack)
        errorstr = [errorstr,' Function: ',ME.stack(1).name,' Line # ',num2str(ME.stack(1).line)];
    end
    if ~isempty(options.logfile)
        DMD_logger(options.logfile,errorstr);
        fprintf(2,errorstr);
    else
        fprintf(2,errorstr);
    end

    status = false;
   DataStruct = [];   
end
   