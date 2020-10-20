function [status, errorstr] = DMD_EDFwrite(HeaderInfo, Data, filename, Annotations, options)
%
% Some notes vefore we start. Generally functions take a matrix of data -
% this assumes that each channel has the same sampling rate. 
%
% EDF, EDF+C, EDF+D
%
% See: https://www.edfplus.info/specs/edf.html
% File Header
%   .DataFormatVersion      [0]
%   .PatientID (Local)          [PatientHospitalAdminCode sex(M/F) birthdate(dd-MMM-yyyy) PatientsName]
%   .RecordingInfo (Local)    [Startdate startdate(dd-MMM-yyyy) StudyHospitalAdminCode Tech/PIHospitalAdminCode EquipHospitalAdminCode]
%   .StartDate                    [startdate(dd.mm.yy)]
%   .StartTime                    [startTime(hh.mm.ss)]
%   .nBytesInHeader
%   .EDFtype                     [EDF or EDF+C or EDF+D]
%   .nDataRecords
%   .DataRecordDuration
%   .nSignals
%
% Channel Header
%   .Label                          [Type Label] See: https://www.edfplus.info/specs/edftexts.html
%   .Transducer                  [Type] (e.g. AgAgCl electrode)
%   .PhysDim                                    See: https://www.edfplus.info/specs/edftexts.html#physidim
%   .PhysMin
%   .PhysMax
%   .DigitalMin
%   .DigitalMax
%   .PreFiltering                  [HP:xx.xxHz LP:xx.xxHz] (e.g. HP:0.1Hz LP:75Hz)
%   .nSamplesInDataRecord
%
% EDF and EDF+ differences
%   1) data records may unconditionally be shorter than 1s
%   2) subsequent data records need not form a continuous recording
%   3) The 'EDF Annotations' signal specially coded to store text annotations, time, events and stimuli.
%
% The Data Record
%   In one datarecord, a maximum of 61440 bytes are available for all signals (including the Annotation signal).
%   Data are encoded as int16 so there are 30720 (61440/2) samples or values avalable in a datarecord. 
%   Choosing a datarecord size is not always straightforward. See: 10 (dec 2005). https://www.edfplus.info/specs/guidelines.html
%       Many people choose 1 second but this can lead to overflow with large numbers of channels
% The samples of an ordinary signal must have equal sample intervals inside each data record, but the interval to the first sample of the next data record may be different.
%       Thus the sample rates maybe differnt on different channels
%
%Time-stamped Annotations Lists (TALs) in an 'EDF Annotations' signal
% The basic structure of a TAL is:
%   +(or-) TimeStamp char(20) EventDescription char(20),char(0)
%
% The part between char(20) and the next char(20) is called one annotation.
%
% The first annotation of the first 'EDF Annotations' signal in each data record is empty, but its timestamp specifies how many seconds after the filestartdate/time that data record starts.
% e.g. +0char(20)char(20)char(0)
% However, you can add other annotations to that time stamp. e.g. +0char(20)char(20)Recording startschar(20)char(0)
%
% Structures:
%   First TAL of a Data Record: +0char(20)char(20)char(0)
%   Time Stamped event (no duration) +0char(20)Recording startschar(20)char(0)
%   SleepScoring interval: char(43) TimeStamp char(21) EventDuration char(20) EventDescription char(20),char(0)... ( +120char(21)5char(20)Sleep stage N2char(20)char(0) )
%   Enviromental disturbance before recording started: char(45) TimeStamp char(21) EventDuration char(20) EventDescription char(20),char(0)... ( -600char(21)5char(20)Janitor Staff Mopping Floorschar(20)char(0) )  


%Annotation Channel

% Inputs
% HeaderInfo
%   .Patient.ID      (e.g. PatientHospitalAdminCode) 
%   .Patient.Sex   (M or F)
%   .Patient.Birthdate
%   .Patient.Name   (Last_First)
%   .Recording.StartDate
%   .Recording.StudyCode
%   .Recording.Technician
%   .Recording.Equipment
%   .StartDate                    [startdate(dd.mm.yy)]
%   .StartTime                    [startTime(hh.mm.ss)]
%   .DataRecordDuration     (optinal if known)
%   .nSignals                     (optinal if known)
%   .Channel.Labels           (cell - optional - needed for Data as a Matrix)
%   .Channel.Transducer     (cell - optional - needed for Data as a Matrix)
%   .Channel.PhysDim        (cell - optional - needed for Data as a Matrix)
%   .Channel.PhysMin         (cell - optional - needed for Data as a Matrix)
%   .Channel.PhysMax        (cell - optional - needed for Data as a Matrix)
%   .Channel.DigitalMin       (cell - optional - needed for Data as a Matrix)
%   .Channel.DigitalMax      (cell - optional - needed for Data as a Matrix)
%   .Channel.PreFiltering     (cell - optional - needed for Data as a Matrix)
%
% Data
% as a Structure
%   .Label                          [Type Label] See: https://www.edfplus.info/specs/edftexts.html
%   .Transducer                  [Type] (e.g. AgAgCl electrode)
%   .PhysDim                                    See: https://www.edfplus.info/specs/edftexts.html#physidim
%   .PhysMin
%   .PhysMax
%   .DigitalMin
%   .DigitalMax
%   .PreFiltering                  [HP:xx.xxHz LP:xx.xxHz] (e.g. HP:0.1Hz (first order) LP:75Hz)
%   .nSamplesInDataRecord
%   .Data
%   .
% as a matrix
%   Rows = samples, Columns = channels
%   NOTE: this only really makes sense if all the data are sampled at the same rate.
%
% filename      (path and filename)
%
%Annotations
%
% options
%   .AllowNonstandardLabels     [logical]   - Pernit Channel labels that do not conform to EDF specs (i.e. AD001)
%   .EDFtype                            [str]       - if exists force a EDF file type
%






