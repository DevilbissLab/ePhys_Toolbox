function [status, nexStruct] = NSB_NEXwriter(nexStruct, fileName)
% write2NexFile is a replacment for writeNexFile
% Written de novo with inspiration from C++ code on Neuroexplorer site.
% Additionally contains abilty to write poulation vectors
%
% Usage:
%  >> [nexStruct] = write2NexFile(nexStruct, fileName)
%
% Inputs:
%   nexStruct   - STRUCT of Nex Data;
%   fileName    - FileName of path+name to be written (optional);
%
% Outputs:
%   nexStruct   - returned nexStruct with updated data fields.
%
% See also: readNexFile for nexStruct structure
%
% Copyright (C) 2010 by David Devilbiss <david.devilbiss@NexStepBiomarkers.com>
%  v. 1.0 DMD 10Oct2010
%
% NOTE: make sure to increment nVar when adding variables to an existing
% structure
status = false;
warning off; %there are conversion rounding warnings

%%
% Initialize variables and collect some information
magicNumber = 827868494; %i.e. 'NEX1'
NexFileHeaderSize = 544;
NexVarHeaderSize = 208;
offsetArray = [];

if (nargin < 2 | length(fileName) == 0)
    [fname, pathname] = uiputfile('*.nex', 'Select a NeuroExplorer file');
    fileName = strcat(pathname, fname);
else
    [pathname, fname, fext] = fileparts(fileName);
    fname = [fname,fext];
end

%Test for Overwrite
if exist(fullfile(pathname, fname),'file') ~= 0
    user = questdlg(['Do you want to overwrite: ',fname],'!! Warning !!','Cancel');
    switch user
        case 'Cancel'
            return;
        case 'No'
            [fname, pathname] = uiputfile('*.nex', 'Create a NeuroExplorer file');
            fileName = strcat(pathname, fname);
    end
end

%make sure num of items = nexStruct.nvar
nNeurons = 0;
nEvents = 0;
nIntervals = 0;
nWaveforms = 0;
nPopvectors = 0;
nCont = 0;
nMarker = 0;
if isfield(nexStruct, 'neurons'), nNeurons = length(nexStruct.neurons); end;
if isfield(nexStruct, 'events'), nEvents = length(nexStruct.events); end;
if isfield(nexStruct, 'intervals'), nIntervals = length(nexStruct.intervals); end;
if isfield(nexStruct, 'waves'), nWaveforms = length(nexStruct.waves); end;
if isfield(nexStruct, 'popvectors'), nPopvectors = length(nexStruct.popvectors); end;
if isfield(nexStruct, 'contvars'), nCont = length(nexStruct.contvars); end;
if isfield(nexStruct, 'markers'), nMarker = length(nexStruct.markers); end;
totalNexDataTypes = nnz([nNeurons,nEvents,nIntervals,nWaveforms,nPopvectors,nCont,nMarker]);
if nNeurons + nEvents + nIntervals + nWaveforms + nPopvectors + nCont + nMarker ~= nexStruct.nvar
    error('Events in structure do not match nVar');
    return;
end

%%
hWaitBar = waitbar(0, ['Please Wait, Saving: ', regexprep(fname, '_', '\\\_')]);
waitbarjump = 0.0666; %total 13 intervals 
% open file
fid = fopen(fileName, 'w+'); %this may need to be just 'W'
if(fid == -1)
    error('Unable to open file');
    return
end

%% write .nex file header
try
waitbar(waitbarjump,hWaitBar);
% write .nex file header
elementCnt = fwrite(fid, magicNumber, 'int32');
elementCnt = fwrite(fid, nexStruct.version, 'int32');

%comment section is 256 elements, buffer with white space.
nexStruct.comment = char(nexStruct.comment, sprintf('%256s',' '));
nexStruct.comment = nexStruct.comment(1,:);

elementCnt = fwrite(fid, nexStruct.comment, 'char');
elementCnt = fwrite(fid, nexStruct.freq, 'double');
elementCnt = fwrite(fid, nexStruct.tbeg.*nexStruct.freq, 'int32');
elementCnt = fwrite(fid, nexStruct.tend.*nexStruct.freq, 'int32');
elementCnt = fwrite(fid, nexStruct.nvar, 'int32');%nvar is number of variables
elementCnt = fwrite(fid, 0, 'int32'); %// position of the next file header in the file not implemented yet
elementCnt = fwrite(fid, sprintf('%256s',' '), 'char'); %padding for future expansion
% end of file header

% sizeof(NexFileHeader) = 544
if ftell(fid) ~= NexFileHeaderSize
    error 'Badly Written Nex File header';
    fclose(fid);
    return;
end

%% Write each Variable Header
%go through each data type and write header
varCounter = 0;
varOffset = NexFileHeaderSize + nexStruct.nvar*NexVarHeaderSize;

for curDataType = 0:6 %7 total data types
    waitbar(waitbarjump + waitbarjump*(curDataType+1),hWaitBar);
    switch curDataType
        case 0
            dynFieldname = 'neurons';
        case 1
            dynFieldname = 'events';
        case 2
            dynFieldname = 'intervals';
        case 3
            dynFieldname = 'waves';
        case 4
            dynFieldname = 'popvectors';
        case 5
            dynFieldname = 'contvars';
        case 6
            dynFieldname = 'markers';
    end

    if isfield(nexStruct, dynFieldname)
        for nItems = 1:length(nexStruct.(dynFieldname));
            varCounter = varCounter +1;
            tempName = [];

            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.type, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.varVersion, 'int32');

            %name section is 64 elements, buffer with white space.
            tempName = char(nexStruct.(dynFieldname){nItems}.name, sprintf('%64s',' '));
            elementCnt = fwrite(fid, tempName(1,:), 'char');

            %test for difference in old/new file offset
            if varOffset ~= nexStruct.(dynFieldname){nItems}.FilePosDataOffset
                nexStruct.(dynFieldname){nItems}.FilePosDataOffset = varOffset;
            end
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.FilePosDataOffset, 'int32');

            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.nEvents, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.WireNumber, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.UnitNumber, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.Gain, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.Filter, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.XPos, 'double');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.YPos, 'double');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.WFrequency, 'double');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.ADtoMV, 'double');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.NPointsWave, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.NMarkers, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.MarkerLength, 'int32');
            elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.MVOfffset, 'double');

            elementCnt = fwrite(fid, sprintf('%60s',' '), 'char'); %padding for future expansion

            %populate offset table
            offsetArray(varCounter,:) = [varCounter, curDataType, nItems, nexStruct.(dynFieldname){nItems}.FilePosDataOffset];

            %Update offset dependent on data type
            % maybe faster/smaller if used sizeof(1,'int32')*nEvents
            switch curDataType
                case {0,1}
                    varOffset = varOffset + sizeof(nexStruct.(dynFieldname){nItems}.timestamps,'int32');
                case 2
                    varOffset = varOffset + 2 * sizeof(nexStruct.(dynFieldname){nItems}.intStarts,'int32');
                case 3
                    varOffset = varOffset + sizeof(nexStruct.(dynFieldname){nItems}.timestamps,'int32');
                    varOffset = varOffset + sizeof(nexStruct.(dynFieldname){nItems}.waveforms,'int16');
                case 4
                    varOffset = varOffset + sizeof(nexStruct.(dynFieldname){nItems}.weights,'double');
                case 5
                    varOffset = varOffset + sizeof(nexStruct.(dynFieldname){nItems}.timestamps,'int32');
                    varOffset = varOffset + sizeof(nexStruct.(dynFieldname){nItems}.fragmentStarts,'int32');
                    varOffset = varOffset + sizeof(nexStruct.(dynFieldname){nItems}.data,'int16');
                case 6
                    varOffset = varOffset + sizeof(nexStruct.(dynFieldname){nItems}.timestamps,'int32');
                    varOffset = varOffset + nexStruct.(dynFieldname){nItems}.NMarkers * ...
                        (sizeof(64,'char') * nexStruct.(dynFieldname){nItems}.MarkerLength);
            end
        end
    end
end

if varCounter == nexStruct.nvar
    disp('Correct Number of Var Headers Written');
else
    error('Incorrect Number of Var Headers Written')
end

%% Write each Variable Data
%go through each data type and write header
varCounter = 0;
for curDataType = 0:6 %7 total data types
     waitbar(8*waitbarjump + waitbarjump*(curDataType+1), hWaitBar);
    switch curDataType
        case 0
            dynFieldname = 'neurons';
            if isfield(nexStruct, dynFieldname)
            for nItems = 1:length(nexStruct.(dynFieldname));
                varCounter = varCounter +1;
                if ftell(fid) ~= offsetArray(varCounter,4)
                    error(['Calculated offset: ',offsetArray(varCounter,4),' ~= current file position: ', ftell(fid)]);
                    %return;
                end
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.timestamps .* nexStruct.freq, 'int32');
            end
            end
        case 1
            dynFieldname = 'events';
            if isfield(nexStruct, dynFieldname)
            for nItems = 1:length(nexStruct.(dynFieldname));
                varCounter = varCounter +1;
                if ftell(fid) ~= offsetArray(varCounter,4)
                    error(['Calculated offset: ',offsetArray(varCounter,4),' ~= current file position: ', ftell(fid)]);
                    %return;
                end
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.timestamps .* nexStruct.freq, 'int32');
            end
            end
        case 2
            dynFieldname = 'intervals';
            if isfield(nexStruct, dynFieldname)
            for nItems = 1:length(nexStruct.(dynFieldname));
                varCounter = varCounter +1;
                if ftell(fid) ~= offsetArray(varCounter,4)
                    error(['Calculated offset: ',offsetArray(varCounter,4),' ~= current file position: ', ftell(fid)]);
                    %return;
                end
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.intStarts .* nexStruct.freq, 'int32');
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.intEnds .* nexStruct.freq, 'int32');
            end
            end
        case 3
            dynFieldname = 'waves';
            if isfield(nexStruct, dynFieldname)
                for nItems = 1:length(nexStruct.(dynFieldname));
                    varCounter = varCounter +1;
                    if ftell(fid) ~= offsetArray(varCounter,4)
                        error(['Calculated offset: ',offsetArray(varCounter,4),' ~= current file position: ', ftell(fid)]);
                        %return;
                    end
                    elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.timestamps .* nexStruct.freq, 'int32');
                    elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.waveforms ./ nexStruct.(dynFieldname){nItems}.ADtoMV, 'int16');

                    %Original way of doing it reshape was not working properly
                    %in this instance

                    % .wave forms is a matrix, 1st linearize it.
                    % the transpose allows reshape to use columns like fread
                    %      wavearray = reshape(nexStruct.(dynFieldname){nItems}.waveforms', 1, nexStruct.(dynFieldname){nItems}.NPointsWave * nexStruct.(dynFieldname){nItems}.nEvents);
                    %      elementCnt = fwrite(fid, wavearray ./ nexStruct.(dynFieldname){nItems}.ADtoMV - ...
                    %       nexStruct.(dynFieldname){nItems}.MVOfffset, 'int16');
                end
            end
        case 4
            dynFieldname = 'popvectors';
            if isfield(nexStruct, dynFieldname)
            for nItems = 1:length(nexStruct.(dynFieldname));
                varCounter = varCounter +1;
                if ftell(fid) ~= offsetArray(varCounter,4)
                    error(['Calculated offset: ',offsetArray(varCounter,4),' ~= current file position: ', ftell(fid)]);
                    %return;
                end
                %elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.weights .* nexStruct.freq, 'float64');
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.weights, 'float64');
            end
            end
        case 5
            dynFieldname = 'contvars';
            if isfield(nexStruct, dynFieldname)
            for nItems = 1:length(nexStruct.(dynFieldname));
                varCounter = varCounter +1;
                if ftell(fid) ~= offsetArray(varCounter,4)
                    error(['Calculated offset: ',offsetArray(varCounter,4),' ~= current file position: ', ftell(fid)]);
                    %return;
                end
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.timestamps .* nexStruct.freq, 'int32');
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.fragmentStarts -1, 'int32');
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.data ./ ...
                    nexStruct.(dynFieldname){nItems}.ADtoMV - nexStruct.(dynFieldname){nItems}.MVOfffset, 'int16');
            end
            end
        case 6
            % this section is broken. possibly deeper data structs ??
            dynFieldname = 'markers';
            if isfield(nexStruct, dynFieldname)
            for nItems = 1:length(nexStruct.(dynFieldname));
                tempName = [];
                varCounter = varCounter +1;
                if ftell(fid) ~= offsetArray(varCounter,4)
                    error(['Calculated offset: ',offsetArray(varCounter,4),' ~= current file position: ', ftell(fid)]);
                    %return;
                end
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.timestamps .* nexStruct.freq, 'int32');

                % element name is 64 elements, buffer with white space.
                tempName = char(nexStruct.(dynFieldname){nItems}.name, sprintf('%64s',' '));
                elementCnt = fwrite(fid, tempName(1,:), 'char');
                
                elementCnt = fwrite(fid, nexStruct.(dynFieldname){nItems}.strings .* nexStruct.freq, 'char');

            end
            end
    end
end
    

%% clean up
waitbar(100,hWaitBar);
fclose(fid);
close(hWaitBar)
disp('File written properly !');
status = true;
catch
waitbar(100,hWaitBar);
fclose(fid);
close(hWaitBar)
disp('File not written properly !');
end
