classdef SignMapperModifR_masked < SignMapperModifR
    % SignMapperModifR_masked
    % Subclass of SignMapperModifR that performs a MASKED (weighted) phase
    % unwrap inside getRetinotopicMap.
    %
    % Why this exists:
    %   The parent's getRetinotopicMap unwraps phase with an UNWEIGHTED
    %   least-squares solver (a global DCT/Poisson solve, phase_unwrap ->
    %   solvePoisson). Because that solve is global, meaningless wrapped-phase
    %   values over cement/skull leak into the brain interior. This subclass
    %   feeds a brain mask in as the unwrap WEIGHT (0 outside the brain), so
    %   masked pixels impose no constraint on the least-squares solution and
    %   the unwrapped values inside the brain are determined by brain pixels
    %   only.
    %
    % Usage:
    %   sm = SignMapperModifR_masked();
    %   sm.ref_img    = first_img;
    %   sm.brain_mask = rot90(brain_mask_raw);  % logical, in phase-map space
    %   k = sm.findRetinotopicMap(fourier_data);
    %   [azi,alt] = sm.getRetinotopicMap(fourier_data,k);
    %
    % When brain_mask is left empty ([]), this class behaves EXACTLY like the
    % stock SignMapperModifR. Nothing on the shared network toolbox is changed;
    % delete this file to revert.
    %
    % NOTE on the mask's coordinate space:
    %   getRetinotopicMap rot90's each phase map internally, so brain_mask must
    %   be supplied in that rotated ("phase-map") space, i.e. rot90 of the
    %   raw-image-space mask. It must match [size(fourier_data,2) size(fourier_data,1)];
    %   a nearest-neighbour resize is applied automatically if it does not.

    properties
        brain_mask = [];   % logical mask in phase-map space; [] => identical to parent
    end

    methods
        function [azimuthMap, altitudeMap] = getRetinotopicMap(obj, fourier_data, h)
            % Overridden to support a weighted (masked) phase unwrap.
            phaseMap = zeros(size(fourier_data,1), size(fourier_data,2), size(fourier_data,4));
            for f = 1:size(fourier_data,4)
                % Inline of the parent's (private) phaseMapChooser: angle, rot90, mean-subtract
                pm = angle(fourier_data(:,:,h,f));
                pm = rot90(pm);
                phaseMap(:,:,f) = pm - mean(pm(:));
            end

            delay_hor  = (exp(1i*phaseMap(:,:,1)) + exp(1i*phaseMap(:,:,2))); % Calculating delay
            delay_vert = (exp(1i*phaseMap(:,:,3)) + exp(1i*phaseMap(:,:,4)));

            delay_hor  = delay_hor  + pi/2*(1-sign(delay_hor));
            delay_vert = delay_vert + pi/2*(1-sign(delay_vert));

            aziPhase = .5*(angle(exp(1i*(phaseMap(:,:,1)-delay_hor)))  - angle(exp(1i*(phaseMap(:,:,2)-delay_hor))));  % Combine opposite directions
            altPhase = .5*(angle(exp(1i*(phaseMap(:,:,3)-delay_vert))) - angle(exp(1i*(phaseMap(:,:,4)-delay_vert))));

            if isempty(obj.brain_mask)
                % Original behaviour: unweighted global unwrap
                azimuthMap  = -phase_unwrap(aziPhase*180/pi);
                altitudeMap = -phase_unwrap(altPhase*180/pi);
            else
                % Masked behaviour: weight the unwrap so cement pixels drop out
                w = double(obj.brain_mask);
                if ~isequal(size(w), size(aziPhase))
                    w = imresize(w, size(aziPhase), 'nearest');
                end
                azimuthMap  = -phase_unwrap(aziPhase*180/pi, w);
                altitudeMap = -phase_unwrap(altPhase*180/pi, w);
            end

            % ---- phase_unwrap (verbatim from SignMapperModifR, both branches) ----
            function phi = phase_unwrap(psi, weight)
                if (nargin < 2) % unweighted phase unwrap
                    % get the wrapped differences of the wrapped values
                    dx = [zeros([size(psi,1),1]), wrapToPi(diff(psi, 1, 2)), zeros([size(psi,1),1])];
                    dy = [zeros([1,size(psi,2)]); wrapToPi(diff(psi, 1, 1)); zeros([1,size(psi,2)])];
                    rho = diff(dx, 1, 2) + diff(dy, 1, 1);

                    % get the result by solving the poisson equation
                    phi = solvePoisson(rho);

                else % weighted phase unwrap
                    % check if the weight has the same size as psi
                    if (~all(size(weight) == size(psi)))
                        error('Argument error: Size of the weight must be the same as size of the wrapped phase');
                    end

                    % vector b in the paper (eq 15) is dx and dy
                    dx = [wrapToPi(diff(psi, 1, 2)), zeros([size(psi,1),1])];
                    dy = [wrapToPi(diff(psi, 1, 1)); zeros([1,size(psi,2)])];

                    % multiply the vector b by weight square (W^T * W)
                    WW = weight .* weight;
                    WWdx = WW .* dx;
                    WWdy = WW .* dy;

                    % applying A^T to WWdx and WWdy is like obtaining rho in the unweighted case
                    WWdx2 = [zeros([size(psi,1),1]), WWdx];
                    WWdy2 = [zeros([1,size(psi,2)]); WWdy];
                    rk = diff(WWdx2, 1, 2) + diff(WWdy2, 1, 1);
                    normR0 = norm(rk(:));

                    % start the iteration
                    eps = 1e-8;
                    k = 0;
                    phi = zeros(size(psi));
                   
                    % reduces the 2-D residual column-wise and stops the moment ANY
                    % column is all-zero -- true as soon as a real (sub-image) mask is
                    % used, so the loop never ran and phi stayed all zeros. Reduce the
                    % whole matrix to a scalar instead: iterate while ANY element is nonzero.
                    while any(rk(:) ~= 0)
                        zk = solvePoisson(rk);
                        k = k + 1;

                        if (k == 1) pk = zk;
                        else
                            betak = sum(sum(rk .* zk)) / sum(sum(rkprev .* zkprev));
                            pk = zk + betak * pk;
                        end

                        % save the current value as the previous values
                        rkprev = rk;
                        zkprev = zk;

                        % perform one scalar and two vectors update
                        Qpk = applyQ(pk, WW);
                        alphak = sum(sum(rk .* zk)) / sum(sum(pk .* Qpk));
                        phi = phi + alphak * pk;
                        rk = rk - alphak * Qpk;

                        % check the stopping conditions
                        if ((k >= numel(psi)) || (norm(rk(:)) < eps * normR0)) break; end;
                    end
                end

                function phi = solvePoisson(rho)
                    % solve the poisson equation using dct
                    dctRho = dct2(rho);
                    [N, M] = size(rho);
                    [I, J] = meshgrid([0:M-1], [0:N-1]);
                    dctPhi = dctRho ./ 2 ./ (cos(pi*I/M) + cos(pi*J/N) - 2);
                    dctPhi(1,1) = 0; % handling the inf/nan value

                    % now invert to get the result
                    phi = idct2(dctPhi);
                end

                function Qp = applyQ(p, WW)
                    % apply (A)
                    dx = [diff(p, 1, 2), zeros([size(p,1),1])];
                    dy = [diff(p, 1, 1); zeros([1,size(p,2)])];

                    % apply (W^T)(W)
                    WWdx = WW .* dx;
                    WWdy = WW .* dy;

                    % apply (A^T)
                    WWdx2 = [zeros([size(p,1),1]), WWdx];
                    WWdy2 = [zeros([1,size(p,2)]); WWdy];
                    Qp = diff(WWdx2,1,2) + diff(WWdy2,1,1);
                end
            end
        end
    end
end