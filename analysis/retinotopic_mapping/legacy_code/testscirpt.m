% ---- set these to your actual entry points ----
entryScript = 'C:\Users\LuanLab\OneDrive - Rice University\Desktop\LGN\Code\Retinotopic_Mapping\Analysis\retinoAnalysis_Xiaorong.m';              % the big script you posted
intanFn     = which('read_Intan_RHD2000_fileV3');
signClass   = which('SignMapperModifR');

% Get dependency lists
req1 = matlab.codetools.requiredFilesAndProducts(entryScript);
req2 = matlab.codetools.requiredFilesAndProducts(intanFn);
req3 = matlab.codetools.requiredFilesAndProducts(signClass);

% Union of all required files
allReq = unique([req1(:); req2(:); req3(:)]);

% Keep only your own code (exclude MATLAB install files)
isUser = ~startsWith(allReq, matlabroot, 'IgnoreCase', true);
userReq = allReq(isUser);

% Copy into a minimal folder
outMin = fullfile(pwd, 'Data_processing_min');
if ~exist(outMin,'dir'), mkdir(outMin); end

for k = 1:numel(userReq)
    [~, name, ext] = fileparts(userReq{k});
    copyfile(userReq{k}, fullfile(outMin, [name ext]));
end

fprintf('Copied %d user files into:\n  %s\n', numel(userReq), outMin);