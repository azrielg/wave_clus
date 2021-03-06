function Do_clustering(input, varargin)

% PROGRAM Do_clustering.
% Does clustering on all files in Files.txt
% Runs after Get_spikes.

% function Do_clustering(input, par_input)
% Saves spikes, spike times (in ms), coefficients used (inspk), used 
% parameters, random spikes selected for clustering (ipermut) and 
% results (cluster_class).

%input must be: 
%               A .txt file with the names of the spikes files to use.
%               A matlab cell with the names of the spikes files to use.
%               A vector, in this case the function will proccessall the
%                   '_spikes.mat' files with that numbers in the folder.
%                   (ipunt=2 don't implies 20 or viceversa)
%               'all', in this case the functions will process all the
%                '_spikes.mat' files in the folder.
% optional argument 'par' and the next input must be a struct with some of
%       the detecction parameters. All the parameters included will 
%       overwrite the parameters load from set_parameters()
% optional argument 'parallel' with the next input true (boolean) for use parallel computing
% optional flag 'make_times' for enable recalculations from 'spikes' files or only plot results.

min_spikes4SPC = 16; % if are less that this number of spikes, clustering won't be made.

%default config
par_input = struct;
parallel = false;
make_times = true;

%search for optional inputs
nvar = length(varargin);
for v = 1:nvar
    if strcmp(varargin{v},'par')
        if (nvar>=v+1) && isstruct(varargin{v+1})
            par_input = varargin{v+1};
        else
            error('Error in ''par'' optional input.')
        end
    elseif strcmp(varargin{v},'parallel')
        if (nvar>=v+1) && islogical(varargin{v+1})
            parallel = varargin{v+1};
        else
            error('Error in ''parallel'' optional input.')
        end
    elseif strcmp(varargin{v},'only_plot')
        make_times = false;
    end
end



% get a cell of filenames from the input
if isnumeric(input) || any(strcmp(input,'all'))  %cases for numeric or 'all' input
    filenames = {};
    dirnames = dir();
    dirnames = {dirnames.name};
    
    for i = 1:length(dirnames)
        fname = dirnames{i};
        
        if length(fname) < 12 
            continue
        end
        if ~ strcmp(fname(end-10:end),'_spikes.mat')
            continue
        end
        if strcmp(input,'all')
            filenames = [filenames {fname}];
        else
            aux = regexp(fname, '\d+', 'match');
            if ismember(str2num(aux{1}),input)
                filenames = [filenames {fname}];   
            end
        end
    end
    
elseif ischar(input) && length(input) > 4 
    if  strcmp (input(end-3:end),'.txt')   %case for .txt input
        filenames =  textread(input,'%s');
    else
        filenames = {input};               %case for cell input
    end

elseif iscellstr(input)
    filenames = input;
else
    ME = MException('MyComponent:noValidInput', 'Invalid input arguments');
    throw(ME)
end

if make_times
% open parallel pool, if parallel input is true
    if parallel == true
        if exist('matlabpool','file')
            try
                matlabpool('open');
            catch
                parallel = false;
            end
        else
            poolobj = gcp('nocreate'); % If no pool, do not create new one.
            if isempty(poolobj)
                parallel = false;
            else
                parpool
            end
        end
    end


    par_file = set_parameters();
    initial_date = now;
    parfor fnum = 1:length(filenames)
        filename = filenames{fnum};
        do_clustering_single(filename,min_spikes4SPC, par_file, par_input);
        disp(sprintf('%d of %d ''times'' files finished.',count_new_times(initial_date, filenames),length(filenames)))
    end

    if parallel == true
        if exist('matlabpool','file')
            matlabpool('close')
        else
            poolobj = gcp('nocreate');
            delete(poolobj);
        end
    end
    
	log_name = 'spc_log.txt';
	f = fopen(log_name, 'w');
	for fnum = 1:length(filenames)
        filename = filenames{fnum};
        log_name = [filename 'spc_log.txt'];
        if exist(log_name, 'file')
			fi = fopen(log_name,'r');
			result = fread(fi);
			fwrite(f,result);
			fclose(fi);
			delete(log_name);
		end
    end
	fclose(f);

	
    disp('Computations Done. Creating figures...')
end

numfigs = length(filenames);
for fnum = 1:numfigs
    filename = filenames{fnum};
    par = struct;
    par.filename = filename;

    par.cont_segment = true;  %maybe true and save the sample in spikes

    data_handler = readInData(par);
    par = data_handler.update_par(par);
    if ~data_handler.with_wc_spikes       			%data should have spikes
        continue
    end
    filename = data_handler.nick_name;

    figure('Visible','Off')
    set(gcf, 'PaperUnits', 'inches', 'PaperType', 'A4', 'PaperPositionMode', 'auto','units','normalized','outerposition',[0 0 1 1]) 
    subplot(3,1,1)
    if par.cont_segment && data_handler.with_psegment
        box off; hold on
        %these lines are for plotting continuous data 
        [xd_sub, sr_sub] = data_handler.get_signal_sample();
        lx = length(xd_sub);
        plot((1:lx)/sr_sub,xd_sub)
        noise_std_detect = median(abs(xd_sub))/0.6745;
        xlim([0 lx/sr_sub])
        thr = par.stdmin * noise_std_detect; 
        thrmax = 15 * noise_std_detect; %thr*par.stdmax/par.stdmin;

        if strcmp(par.detection,'pos')
            line([0 length(xd_sub)/sr_sub],[thr thr],'color','r')
            ylim([-thrmax/2 thrmax])
        elseif strcmp(par.detection,'neg')
            line([0 length(xd_sub)/sr_sub],[-thr -thr],'color','r')
            ylim([-thrmax thrmax/2])
        else
            line([0 length(xd_sub)/sr_sub],[thr thr],'color','r')
            line([0 length(xd_sub)/sr_sub],[-thr -thr],'color','r')
            ylim([-thrmax thrmax])
        end
    end
    title([pwd '/' filename],'Interpreter','none','Fontsize',14)

    if ~data_handler.with_spc  
        print2file = par_file.print2file;
        if isfield(par_input,'print2file')
            print2file = par_input.print2file;
        end    
        if print2file;
            print(gcf,'-dpng',['fig2print_' filename '.png'],'-r200');
        else
            print
        end
        clear print2file
        fprintf('%d figs Done. ',fnum);
        continue
    end
        
    % LOAD SPIKES        
    [clu, tree, spikes, index, inspk, ipermut, classes, forced] = data_handler.load_results();
    nspk = size(spikes,1);
    [temp] = find_temp(tree,par);
 
    

    %PLOTS
    clus_pop = [];
    ylimit = [];
    subplot(3,5,11)
    temperature = par.mintemp+temp*par.tempstep;
    color =['b' 'r' 'g' 'c' 'm' 'y' 'b' 'r' 'g' 'c' 'm' 'y' 'b' 'k' 'b' 'r' 'g' 'c' 'm' 'y' 'b' 'r' 'g' 'c' 'm' 'y' 'b' 'k' 'b' 'r' 'g' 'c' 'm' 'y' 'b' 'r' 'g' 'c' 'm' 'y' 'b'];

    hold on 
    num_temp = floor((par.maxtemp -par.mintemp)/par.tempstep);     % total number of temperatures
    switch par.temp_plot
            case 'lin'
                plot([par.mintemp par.maxtemp-par.tempstep], ...
                [par.min_clus par.min_clus],'k:',...
                par.mintemp+(1:num_temp)*par.tempstep, ...
                tree(1:num_temp,5:size(tree,2)),[temperature temperature],[1 tree(1,5)],'k:')
            
                for i=1:max(classes)
                    tree_clus = tree(temp,4+i);
                    tree_temp = tree(temp+1,2);
                    plot(tree_temp,tree_clus,'.','color',color(i),'MarkerSize',20);
                end
            case 'log'
                set(gca,'yscale','log');
                semilogy([par.mintemp par.maxtemp-par.tempstep], ...
                [par.min_clus par.min_clus],'k:',...
                par.mintemp+(1:num_temp)*par.tempstep, ...
                tree(1:num_temp,5:size(tree,2)),[temperature temperature],[1 tree(1,5)],'k:')
                
                for i=1:max(classes)
                    tree_clus = tree(temp,4+i);
                    tree_temp = tree(temp+1,2);
                    semilogy(tree_temp,tree_clus,'.','color',color(i),'MarkerSize',20);
                end
    end
    xlim([par.mintemp, par.maxtemp])
    subplot(3,5,6)
    hold on
    

    class0 = find(classes==0);
        max_spikes=min(length(class0),par.max_spikes_plot);
        plot(spikes(class0(1:max_spikes),:)','k'); 
        xlim([1 size(spikes,2)]);
    subplot(3,5,10); 
        hold on
        plot(spikes(class0(1:max_spikes),:)','k');  
        plot(mean(spikes(class0,:),1),'c','linewidth',2)
        xlim([1 size(spikes,2)]); 
        title(['Cluster 0: # ' num2str(length(class0))],'Fontweight','bold')
    subplot(3,5,15)
        xa=diff(index(class0));
        [n,c]=hist(xa,0:1:100);
        bar(c(1:end-1),n(1:end-1))
        xlim([0 100])
        xlabel('ISI (ms)');
        title([num2str(nnz(xa<3)) ' in < 3ms']);

    
        
    for i = 1:min(max(classes),3)
        class = find(classes==i);
        subplot(3,5,6); 
            max_spikes=min(length(class),par.max_spikes_plot);
            plot(spikes(class(1:max_spikes),:)','color',color(i)); 
            xlim([1 size(spikes,2)]);
        subplot(3,5,6+i); 
            hold on
            plot(spikes(class(1:max_spikes),:)','color',color(i)); 
            plot(mean(spikes(class,:),1),'k','linewidth',2)
            xlim([1 size(spikes,2)]); 
            title(['Cluster ' num2str(i) ': # ' num2str(length(class)) ' (' num2str(nnz(classes(:)==i & ~forced(:))) ')'],'Fontweight','bold')
            ylimit = [ylimit;ylim];
        subplot(3,5,11+i)
        xa=diff(index(class));
        [n,c]=hist(xa,0:1:100);
        bar(c(1:end-1),n(1:end-1))
        xlim([0 100])
        xlabel('ISI (ms)');
        title([num2str(nnz(xa<3)) ' in < 3ms']);
        
    end

    % Rescale spike's axis 
    if ~isempty(ylimit)
        ymin = min(ylimit(:,1));
        ymax = max(ylimit(:,2));
        for i = 1:min(3,max(classes))
           subplot(3,5,6+i); ylim([ymin ymax]);
        end
    end

    features_name = par.features;

    numclus = max(classes);
    outfileclus='cluster_results.txt';
    fout=fopen(outfileclus,'at+');
    if isfield(par,'stdmin')
        stdmin = par.stdmin;
    else
        stdmin = NaN;
    end
    fprintf(fout,'%s\t %s\t %g\t %d\t %g\t', char(filename), features_name, temperature, numclus, stdmin);
    for ii=0:numclus
        fprintf(fout,'%d\t',nnz(classes==ii));
    end
    fclose(fout);

    
    
    if par.print2file;
        print(gcf,'-dpng',['fig2print_' filename '.png'],'-r200');
    else
        print
    end 
    fprintf('%d ',fnum);
end
disp(' ')

end

function do_clustering_single(filename,min_spikes4SPC, par_file, par_input)
    
    par = struct;
    par = update_parameters(par,par_file,'clus');
    
    if isfield(par,'channels')
        par.inputs = par.inputs * par.channels;
    end
    par.filename = filename;
    par.reset_results = true;
    
    data_handler = readInData(par);
    par = data_handler.par;
    
    if isfield(par,'channels')
        par.inputs = par.inputs * par.channels;
    end
    
    par.fname_in = ['tmp_data_wc' data_handler.nick_name];                       % temporary filename used as input for SPC
    par.fname = ['data_' data_handler.nick_name];
    par.nick_name = data_handler.nick_name;
    par.fnamespc = par.fname;                  		%filename if "save clusters" button is pressed

    par = update_parameters(par,par_input,'clus');
    
    
    if data_handler.with_spikes            			%data have some time of _spikes files
        [spikes, index] = data_handler.load_spikes(); 
    else
        warning('MyComponent:noValidInput', 'File: %s doesn''t include spikes', filename);
        throw(ME)
        return 
    end
        
    % LOAD SPIKES
    nspk = size(spikes,1);
    naux = min(par.max_spk,size(spikes,1));
    par.min_clus = max(par.min_clus,par.min_clus_rel*naux);
    
	
    if nspk < min_spikes4SPC     
        warning('MyComponent:noValidInput', 'Not enough spikes in the file');
        return
    end
    
    % CALCULATES INPUTS TO THE CLUSTERING ALGORITHM. 
    inspk = wave_features(spikes,par);     %takes wavelet coefficients.

	if par.permut == 'n'
        % GOES FOR TEMPLATE MATCHING IF TOO MANY SPIKES.
        if size(spikes,1)> par.max_spk;
            % take first 'par.max_spk' spikes as an input for SPC
            inspk_aux = inspk(1:naux,:);
        else
            inspk_aux = inspk;
        end   
	else
        % GOES FOR TEMPLATE MATCHING IF TOO MANY SPIKES.
        if size(spikes,1)> par.max_spk;
            % random selection of spikes for SPC 
            ipermut = randperm(length(inspk));
            ipermut(naux+1:end) = [];
            inspk_aux = inspk(ipermut,:);
        else
            ipermut = randperm(size(inspk,1));
            inspk_aux = inspk(ipermut,:);
        end 
	end
    %INTERACTION WITH SPC
    save(par.fname_in,'inspk_aux','-ascii');
    try
        [clu, tree] = run_cluster(par,true);
    catch
        warning('MyComponent:ERROR_SPC', 'Error in SPC');
        return
    end
    [temp] = find_temp(tree,par);
    

    if par.permut == 'y'
        clu_aux = zeros(size(clu,1),size(spikes,1)) -1;% + 1000; %when update classes from clu, not selected go to cluster 1001
        clu_aux(:,ipermut+2) = clu(:,(1:length(ipermut))+2);
        clu_aux(:,1:2) = clu(:,1:2);
        clu = clu_aux;
        clear clu_aux
    end
    classes = clu(temp,3:end)+1;
    if par.permut == 'n'
        classes = [classes zeros(1,max(size(spikes,1)-par.max_spk,0))];
    end
    
    for i = 1:max(classes)
        if nnz(classes==i) < par.min_clus
            classes(classes==i) = 0;
        end
    end
    Temp = [];
    % Classes should be consecutive numbers
    classes_names = nonzeros(sort(unique(classes)));
    for i= 1:length(classes_names)
       c = classes_names(i);
       if c~= i
           classes(classes == c) = i;
       end
       Temp(i) = temp;
    end
    
    
    % IF TEMPLATE MATCHING WAS DONE, THEN FORCE
    if (size(spikes,1)> par.max_spk || ...
            (par.force_auto))
        f_in  = spikes(classes~=0,:);
        f_out = spikes(classes==0,:);
        class_in = classes(classes~=0);
        class_out = force_membership_wc(f_in, class_in, f_out, par);
        forced = classes==0;
        classes(classes==0) = class_out;
        forced(classes==0) = 0;
    else
        forced = zeros(1, size(spikes,1));
    end
    current_par = par;
    par = struct;
    par = update_parameters(par, current_par, 'relevant');
    par.min_clus_rel = current_par.min_clus_rel;
    cluster_class = zeros(nspk,2);
    cluster_class(:,2)= index';
    cluster_class(:,1)= classes';
    save(['times_' data_handler.nick_name], 'cluster_class','spikes', 'index', 'par','inspk','forced','Temp');
    if exist('ipermut','var')
        save(['times_' data_handler.nick_name],'ipermut','-append');
    end
end
    
function counter = count_new_times(initial_date, filenames)
counter = 0;
for i = 1:length(filenames)
    fname = filenames{i};
    FileInfo = dir(['times_' fname(1:end-11) '.mat']);
    if length(FileInfo)==1 && (FileInfo.datenum > initial_date)
        counter = counter + 1;
    end
end
end

