% The COBRAToolbox: testCycleFreeFlux.m
%
% Purpose:
%     - Test whether cycleFreeFlux removes flux around stoichiometrically
%       balanced cycles from FBA solutions for the E. coli core model
%
% Authors:
%     - Original file: Hulda S. Haraldsdottir 03/08/2018
%

global CBTDIR

% define the features required to run the test

% require the specified toolboxes and solvers, along with a UNIX OS
solverPkgs = prepareTest('needsLP', true);

% save the current path
currentDir = pwd;

% initialize the test
cd(fileparts(which(mfilename)));

% set the tolerance
tol = getCobraSolverParams('LP', 'feasTol');

% load the model
%Either:
model = getDistributedModel('ecoli_core_model.mat'); %For all models in the test/models folder and subfolders
[~, isInternalRxn] = findStoichConsistentSubset(model, 0, 0);
cycleRxns = {'FRD7'; 'SUCDi'}; % Form a stoichiometrically balanced cycle
isCycleRxn = ismember(model.rxns, cycleRxns);

try
    parTest = true;
    poolobj = gcp('nocreate'); % if no pool, do not create new one.
    if isempty(poolobj)
        parpool(2); % launch 2 workers
    end
catch ME
    parTest = false;
    fprintf('No Parallel Toolbox found. Trying test without Parallel toolbox.\n')
end

for k = 1:length(solverPkgs.LP)
    fprintf(' -- Running testCycleFreeFlux using the solver interface: %s ... ', solverPkgs.LP{k});

    solverLPOK = changeCobraSolver(solverPkgs.LP{k}, 'LP', 0);

    if solverLPOK
        % Remove cycle from a single FBA solution
        solution = optimizeCbModel(model);
        v1 = cycleFreeFlux(solution.v, model.c, model, isInternalRxn);
        d1 = v1 - solution.v;
        assert(norm(d1(isCycleRxn)) > 500);
        assert(norm(d1(~isCycleRxn)) <= tol);
        
        % Attempt to remove a forced cycle
        model.lb(find(isCycleRxn, 1)) = 1000; % Force flux through FRD7
        solution = optimizeCbModel(model);
        
        relaxBounds = false; % Default
        v2 = cycleFreeFlux(solution.v, model.c, model, isInternalRxn, relaxBounds);
        d2 = v2 - solution.v;
        assert(norm(d2) <= tol);
        
        relaxBounds = true; % Relax flux bounds that do not include 0
        v3 = cycleFreeFlux(solution.v, model.c, model, isInternalRxn, relaxBounds);
        d3 = v3 - solution.v;
        assert(norm(d3(isCycleRxn)) > 500);
        assert(norm(d3(~isCycleRxn)) <= tol);
        
        % Remove cycle from a set of flux vectors
        model.lb(find(isCycleRxn, 1)) = 0; % Reset lower bound on FRD7
        [minFlux, maxFlux, Vmin, Vmax] = fluxVariability(model, 0, 'max', model.rxns, 0, 1, 'FBA');
        V0 = [Vmin, Vmax];
        n = size(model.S, 2);
        C = [eye(n), eye(n)];
        relaxBounds = false;
        V1 = cycleFreeFlux(V0, C, model, isInternalRxn, relaxBounds, parTest);
        D1 = V1 - V0;
        assert(norm(D1(isCycleRxn, :)) > 500);
        assert(norm(D1(~isCycleRxn, :)) <= tol);
    end
    
    % output a success message
    fprintf('Done.\n');
end

% change the directory
cd(currentDir)
