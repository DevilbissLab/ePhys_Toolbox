function [ret, msg] = Borealis_WriteEDF(DataStruct, parms, options)
%
% write a file for each epoch (EDF+D can handle this but not vanilla EDF+C)
% options.SaveDir
% options.writeAsBlock
% options.writeWAV
% 
%issues with naming!


ret = false; msg = '';
data = [];HDR.labels = cell(0);HDR.digmin = []; HDR.digmax = []; HDR.physmin = []; HDR.physmax =[];

if isempty(options)
    options.null = NaN;
end
if ~isfield(options,'writeAsBlock')
    options.writeAsBlock = false;
end
if ~isfield(options,'writeWAV')
    options.writeWAV = false;
end
if ~isfield(options,'SaveDir')
    options.SaveDir = 'F:\mTBI_Data\ServerSide_Analytics-EDFOutput';
end

try
    for curFile = 1:length(DataStruct.Epoch)
        if DataStruct.Epoch{curFile}.validData && ~DataStruct.Epoch{curFile}.IgnoreData
            
            if options.writeWAV
                % get scaling value
                wavScale = floor(max(abs(DataStruct.Epoch{curFile}.rawEEG.data)));
                wavFileName = fullfile(options.SaveDir, [regexprep(DataStruct.Epoch{curFile}.protocol,':\s','_'), '_Ch',num2str(curFile),'.wav']);
                %24 bit
                % wavwrite(DataStruct.Epoch{curFile}.rawEEG.data / wavScale, DataStruct.sRate, 24, wavFileName);
                % 16 bit
                %wavwrite(DataStruct.Epoch{curFile}.rawEEG.data / wavScale, DataStruct.sRate, 16, wavFileName);
                audiowrite(wavFileName, DataStruct.Epoch{curFile}.rawEEG.data / wavScale, DataStruct.sRate, 16);
                disp(['.wav file scale = ',num2str(wavScale), ' ',wavFileName]);
                
            end
            
            %Build HDR
            HDR.patient.ID  = DataStruct.subject;
            HDR.patient.Sex = DataStruct.gender(1);
            try
            HDR.patient.BirthDate = datestr(datenum(DataStruct.birthdate),1);
            catch
                %May have used periods
                DataStruct.birthdate = regexprep(DataStruct.birthdate,'\.','-');
                HDR.patient.BirthDate = datestr(datenum(DataStruct.birthdate),1);
            end
            HDR.patient.Name = DataStruct.subjectInitials;
            HDR.record.ID = regexprep(DataStruct.address,',\s','_');
            HDR.record.Tech = DataStruct.tech;
            %HDR.record.Eq = regexprep(['Cerora_',DataStruct.HeadSetModel{1},'_',DataStruct.sernum],'\s','_');
            HDR.record.Eq = regexprep([DataStruct.HeadSetModel{1},'_',DataStruct.sernum],'\s','_');
            try
                HDR.startdate = datestr(datenum(DataStruct.Epoch{curFile}.date),1);
                HDR.starttime = datestr(datenum(DataStruct.Epoch{curFile}.date),13);
            catch
                HDR.startdate = 'X';
                HDR.starttime = [];
            end
            
            HDR.duration = DataStruct.Epoch{curFile}.rawEEG.ts(end) - DataStruct.Epoch{curFile}.rawEEG.ts(1);
            HDR.samplerate = DataStruct.sRate;
            %HDR.labels = {'FP1'};
            HDR.transducer = ' ';
            HDR.units = 'uV';
            HDR.prefilt  = 'HP:0.5Hz LP:100Hz N:60Hz';
            %

            
            if options.writeAsBlock
                HDR.digmax = 32767;
                HDR.digmin = -32768;
                physmin = min(DataStruct.Epoch{curFile}.rawEEG.data);
                physmax = max(DataStruct.Epoch{curFile}.rawEEG.data);
                minmax = ceil(max(abs(physmin), abs(physmax)));
                
                if ~parms.Analytics.Debug.Write_Artifact_Interpolating
                    data = [data, DataStruct.Epoch{curFile}.rawEEG.data(:) * HDR.digmax/minmax];
                else 
                    data = [data, DataStruct.Epoch{curFile}.rawEEG.DetrendData(:) * HDR.digmax/minmax];
                end
                
%                 Commented to address detrended data
%                 data = [data, DataStruct.Epoch{curFile}.rawEEG.data(:) * HDR.digmax/minmax];
                HDR.labels{curFile} = regexprep(DataStruct.Epoch{curFile}.protocol,':\s','_');
                
                HDR.physmin = [HDR.physmin, min(-minmax, physmin)];  %physical minimum  
                HDR.physmax = [HDR.physmax, minmax]; %physical maximum  
                
            else
%                 HDR.digmin = min(DataStruct.Epoch{curFile}.rawEEG.data); % digital minimum
%                 HDR.digmax = max(DataStruct.Epoch{curFile}.rawEEG.data);  %digital maximum
%                 HDR.physmin = min(DataStruct.Epoch{curFile}.rawEEG.data);  %physical minimum  
%                 HDR.physmax = max(DataStruct.Epoch{curFile}.rawEEG.data); %physical maximum 
            HDR.physmax = 32767;    
            HDR.physmin = -32768;
            HDR.digmax = 32767;
            HDR.digmin = -32768; 
                HDR.labels = {'FP1'};
                if isfield(DataStruct.Epoch{curFile},'Artifacts')
                HDR.annotation.event = repmat({'Artifact Start'},length(DataStruct.Epoch{curFile}.Artifacts.ArtifactStruct.intStarts),1);
                HDR.annotation.duration = DataStruct.Epoch{curFile}.Artifacts.ArtifactStruct.intEnds - DataStruct.Epoch{curFile}.Artifacts.ArtifactStruct.intStarts;
                HDR.annotation.starttime = DataStruct.Epoch{curFile}.Artifacts.ArtifactStruct.intStarts;
                HDR.annotation.event = [HDR.annotation.event; repmat({'End Artifact'},length(DataStruct.Epoch{curFile}.Artifacts.ArtifactStruct.intEnds),1)];
                HDR.annotation.duration = [HDR.annotation.duration; zeros(length(DataStruct.Epoch{curFile}.Artifacts.ArtifactStruct.intEnds),1)];
                HDR.annotation.starttime = [HDR.annotation.starttime; DataStruct.Epoch{curFile}.Artifacts.ArtifactStruct.intEnds];
                else
                HDR.annotation.event = {'Start'};
                HDR.annotation.duration = 0;
                HDR.annotation.starttime = 0;
                end
                
                if ~parms.Analytics.Debug.Write_Artifact_Interpolating
                    data = DataStruct.Epoch{curFile}.rawEEG.data;
                else 
                    data = DataStruct.Epoch{curFile}.rawEEG.DetrendData;
                end
                    
                FileName = fullfile(options.SaveDir, [regexprep(DataStruct.Epoch{curFile}.protocol,':\s','_'), '_(1).edf']);
                if exist(FileName,'file') ~= 0
                    [idx, outFileName, flf_status] = DMD_findLastFile('(1)', FileName);
                    if isnumeric(idx)
                        nextIDX = num2str(idx+1);
                    elseif ischar(idx)
                        nextIDX = char(double(idx)+1); %Make it the next letter;
                    end
                    FileName = fullfile(options.SaveDir, [regexprep(DataStruct.Epoch{curFile}.protocol,':\s','_'), '_(',nextIDX,').edf']);
                end
                
                %given that these sample rates are not necessarily correct, the EDF may be
                %malformed so fix now.
                if length(data) > HDR.duration * HDR.samplerate
                    data(HDR.duration * HDR.samplerate +1: end) = [];
                end
                SaveEDF(FileName, data, HDR);
            end
        end
    end
    if options.writeAsBlock
        HDR.annotation.event = {'Start'};
        HDR.annotation.duration = 0;
        HDR.annotation.starttime = 0;
        FileName = fullfile(options.SaveDir, ['Data.edf']);
        if size(data,1) > HDR.duration * HDR.samplerate
            data(HDR.duration * HDR.samplerate +1: end,:) = [];
        end
        SaveEDF(FileName, data, HDR);
    end

    ret = true;
catch ME
    Borealis_ReportError(ME, options)
    msg = ME.message;
end

