%% diagnose_late_segment_matching.m
%
% 读取后段 TIFF 嵌入时间戳（文件 FIRST_LATE_TIFF .. N_TIFF）
% 以及对应的 SMA1 触发时间（触发 FIRST_LATE_TIFF .. N_SMA1），
% 找出哪些 SMA1 触发没有对应的 TIFF，把它们列出来并保存。
%
% 保存变量（late_segment_timestamps.mat）：
%   tiff_t_late               [1 x N_LATE]  每张后段 TIFF 的嵌入时间戳 (s, 相机时钟)
%   sma1_t_late               [1 x N_SMA1_LATE]  对应 SMA1 触发时间 (s, Ripple 时钟)
%   unmatched_sma1_global_idx [1 x N_drop]  没匹配到 TIFF 的 SMA1 全局编号 (1-based)
%   unmatched_sma1_time_s     [1 x N_drop]  对应的 Ripple 会话时间 (s)

clear; clc;

%% ============================================================
%  参数
%% ============================================================
%FIRST_LATE_TIFF = 29173;   % 后段第一个可能有丢帧的 TIFF 位置（1-based 排序后编号）
FIRST_LATE_TIFF = 1;   % 后段第一个可能有丢帧的 TIFF 位置（1-based 排序后编号）
MATCH_TOL_S     = 0.05;    % 匹配容差 (s)，10 Hz 帧间距 0.1 s，取一半
EMA_ALPHA       = 0.02;    % EMA 平滑系数，用于追踪两个时钟之间的缓慢漂移
DISCONTINUITY_S = 2.0;     % TIFF 时间戳跳变阈值 (s)，超过则重新锚定偏移量

%% ============================================================
%  交互式路径选择
%% ============================================================
fprintf('请选择 ripple_timing.mat（Step 1 输出）...\n');
[rt_name, rt_path] = uigetfile('*.mat', '选择 ripple_timing.mat');
if isequal(rt_name, 0), error('未选择文件，已取消。'); end
RIPPLE_TIMING_MAT = fullfile(rt_path, rt_name);

fprintf('请选择包含所有 TIFF 图像的文件夹...\n');
TIFF_DIR = uigetdir(rt_path, '选择 TIFF 图像文件夹');
if isequal(TIFF_DIR, 0), error('未选择文件夹，已取消。'); end

fprintf('请选择保存结果的文件夹...\n');
SAVE_DIR = uigetdir(rt_path, '选择保存文件夹');
if isequal(SAVE_DIR, 0), error('未选择文件夹，已取消。'); end

fprintf('\nripple_timing : %s\n', RIPPLE_TIMING_MAT);
fprintf('TIFF 文件夹   : %s\n', TIFF_DIR);
fprintf('保存文件夹    : %s\n\n', SAVE_DIR);

%% ============================================================
%  1. 读取 SMA1 触发时间
%% ============================================================
rt            = load(RIPPLE_TIMING_MAT, 'ripple_timing');
frame_times_s = double(rt.ripple_timing.frames.time_s(:)');
N_SMA1        = numel(frame_times_s);
sma1_t_late   = frame_times_s(FIRST_LATE_TIFF : end);   % 后段 SMA1 时间
N_SMA1_LATE   = numel(sma1_t_late);

fprintf('SMA1 总触发数        : %d\n', N_SMA1);
fprintf('后段 SMA1 触发数     : %d  (触发 #%d .. #%d)\n', ...
    N_SMA1_LATE, FIRST_LATE_TIFF, N_SMA1);

%% ============================================================
%  2. 找到并排序所有 TIFF 文件
%% ============================================================
raw = [dir(fullfile(TIFF_DIR,'*.tif')); dir(fullfile(TIFF_DIR,'*.tiff'))];
assert(~isempty(raw), 'TIFF 文件夹中没有找到 .tif/.tiff 文件：\n  %s', TIFF_DIR);

file_nums = nan(numel(raw), 1);
for i = 1:numel(raw)
    tok = regexp(raw(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    if ~isempty(tok), file_nums(i) = str2double(tok{1}); end
end
valid = isfinite(file_nums);
raw   = raw(valid);
file_nums = file_nums(valid);
[~, ord]  = sort(file_nums);
files  = raw(ord);
N_TIFF = numel(files);
N_LATE = N_TIFF - FIRST_LATE_TIFF + 1;   % 后段 TIFF 数量

fprintf('TIFF 总文件数        : %d\n', N_TIFF);
fprintf('后段 TIFF 文件数     : %d  (排序位置 #%d .. #%d)\n', ...
    N_LATE, FIRST_LATE_TIFF, N_TIFF);
fprintf('预期未匹配（丢帧）数 : %d\n\n', N_SMA1_LATE - N_LATE);

%% ============================================================
%  3. 读取后段每个 TIFF 的嵌入时间戳
%% ============================================================
fprintf('正在读取 TIFF 嵌入时间戳（仅读 IFD 头，不加载像素）...\n');
tiff_t_late = nan(1, N_LATE);
t0 = tic;
for k = 1:N_LATE
    fpath = fullfile(TIFF_DIR, files(FIRST_LATE_TIFF + k - 1).name);
    try
        tf   = Tiff(fpath, 'r');
        desc = tf.getTag('ImageDescription');
        tf.close();
        tok  = regexp(desc, 'Time_From_Start\s*=\s*(\d+):(\d+):([\d.]+)', 'tokens', 'once');
        if ~isempty(tok)
            tiff_t_late(k) = str2double(tok{1})*3600 + ...
                             str2double(tok{2})*60   + ...
                             str2double(tok{3});
        end
    catch
        % 保持 NaN
    end
    if mod(k, 5000) == 0 || k == N_LATE
        fprintf('  %d / %d  （已用 %.0f s）\n', k, N_LATE, toc(t0));
    end
end

n_parsed = sum(isfinite(tiff_t_late));
fprintf('成功解析时间戳：%d / %d\n\n', n_parsed, N_LATE);
if n_parsed < N_LATE
    warning('%d 个 TIFF 无法解析时间戳（已保留为 NaN）。', N_LATE - n_parsed);
end

%% ============================================================
%  4. 扫描 TIFF 时间戳的跳变点（用于重新锚定）
%% ============================================================
dt_tiff  = diff(tiff_t_late);
disc_k   = find(dt_tiff > DISCONTINUITY_S | dt_tiff < -MATCH_TOL_S) + 1;
disc_set = false(1, N_LATE);
disc_set(disc_k) = true;

if isempty(disc_k)
    fprintf('未检测到时间戳跳变。\n\n');
else
    fprintf('检测到 %d 处时间戳跳变（将在该处重新锚定偏移量）：\n', numel(disc_k));
    for di = 1:numel(disc_k)
        fprintf('  后段位置 k=%d（全局文件 #%d），跳变量 = %.2f s\n', ...
            disc_k(di), FIRST_LATE_TIFF + disc_k(di) - 1, dt_tiff(disc_k(di)-1));
    end
    fprintf('\n');
end

%% ============================================================
%  5. 逐帧匹配：SMA1 触发时间 ↔ TIFF 嵌入时间戳
%     - 匹配上 → 两个指针同步前进
%     - 匹配不上 → 该 SMA1 触发记为"未匹配"，TIFF 指针不动
%     - 遇到跳变 → 重新锚定偏移量后继续
%     - EMA → 每次匹配成功后微调偏移量，追踪缓慢时钟漂移
%% ============================================================
current_offset = sma1_t_late(1) - tiff_t_late(1);   % 初始锚定

unmatched_j = [];   % 后段内的相对索引（1-based，对应 sma1_t_late）
k_tiff = 1;

for j = 1:N_SMA1_LATE

    if k_tiff > N_LATE
        % TIFF 已用完，剩余所有 SMA1 触发均未匹配
        unmatched_j = [unmatched_j, j : N_SMA1_LATE];  %#ok<AGROW>
        break;
    end

    % 遇到跳变点 → 重新锚定
    if disc_set(k_tiff)
        old_off = current_offset;
        current_offset = sma1_t_late(j) - tiff_t_late(k_tiff);
        disc_set(k_tiff) = false;
        fprintf('  [重新锚定] SMA1 #%d ↔ TIFF 全局 #%d  偏移 %+.4f → %+.4f s\n', ...
            FIRST_LATE_TIFF + j - 1, ...
            FIRST_LATE_TIFF + k_tiff - 1, ...
            old_off, current_offset);
    end

    dist = abs(tiff_t_late(k_tiff) + current_offset - sma1_t_late(j));

    if dist <= MATCH_TOL_S
        % 匹配成功：EMA 更新偏移量
        current_offset = (1 - EMA_ALPHA) * current_offset + ...
                         EMA_ALPHA       * (sma1_t_late(j) - tiff_t_late(k_tiff));
        k_tiff = k_tiff + 1;
    else
        % 未匹配：该 SMA1 触发没有对应 TIFF
        unmatched_j(end+1) = j;  %#ok<AGROW>
    end

end

%% ============================================================
%  6. 整理输出变量
%% ============================================================
% 转换为全局 SMA1 编号（1-based，与 frame_times_s 对齐）
unmatched_sma1_global_idx = uint32(FIRST_LATE_TIFF - 1 + unmatched_j);
unmatched_sma1_time_s     = frame_times_s(unmatched_sma1_global_idx);

% delta_t(i) = tiff_t_late(i) - sma1_t_late(i)
% 直接按索引对齐相减，不考虑丢帧。
% 两个时钟零点不同，所以 delta_t 有一个固定偏置（两台设备的时钟差）。
% 每发生一次丢帧，delta_t 会阶跃约 +0.1 s（该 TIFF 对应的是下一个 SMA1 触发）。
% 时间戳跳变处会有明显的大幅跳变。
N_compare = min(N_LATE, N_SMA1_LATE);
delta_t   = tiff_t_late(1:N_compare) - sma1_t_late(1:N_compare);  % [1 x N_compare]

%% ============================================================
%  7. 打印结果
%% ============================================================
fprintf('\n=== delta_t = tiff_t_late(i) - sma1_t_late(i) 统计 ===\n');
fprintf('  元素数      : %d\n',   N_compare);
fprintf('  初始值      : %+.4f s\n', delta_t(1));
fprintf('  末尾值      : %+.4f s\n', delta_t(end));
fprintf('  总变化量    : %+.4f s\n', delta_t(end) - delta_t(1));
fprintf('  min         : %+.4f s\n', min(delta_t));
fprintf('  max         : %+.4f s\n', max(delta_t));

fprintf('\n=== 未匹配的 SMA1 触发（丢失的 TIFF 帧）===\n');
fprintf('  %-5s  %-12s  %-16s\n', '序号', 'SMA1 全局编号', '会话时间 (s)');
fprintf('  %s\n', repmat('-', 1, 38));
for i = 1:numel(unmatched_sma1_global_idx)
    fprintf('  %-5d  %-12d  %.4f\n', ...
        i, unmatched_sma1_global_idx(i), unmatched_sma1_time_s(i));
end
fprintf('\n总计未匹配：%d  （预期 %d）\n', ...
    numel(unmatched_sma1_global_idx), N_SMA1_LATE - N_LATE);

%% ============================================================
%  8. 绘图
%% ============================================================
fig = figure('Color','w','Name','delta_t diagnostic','Position',[50 50 1300 480]);
tl  = tiledlayout(fig, 1, 2, 'TileSpacing','compact','Padding','compact');

frame_idx_compare = (FIRST_LATE_TIFF : FIRST_LATE_TIFF + N_compare - 1);

ax1 = nexttile(tl);
plot(ax1, frame_idx_compare, delta_t, '.', 'MarkerSize', 2, 'Color', [0.2 0.5 0.9]);
xlabel(ax1, 'TIFF 排序位置（即 TIFF 序号）');
ylabel(ax1, 'delta\_t = tiff\_t - sma1\_t  (s)');
title(ax1, 'delta\_t 随帧序号的变化');
grid(ax1, 'on');

ax2 = nexttile(tl);
histogram(ax2, delta_t, 200, 'FaceColor',[0.2 0.5 0.9], 'EdgeColor','none');
xlabel(ax2, 'delta\_t (s)');
ylabel(ax2, '帧数');
title(ax2, 'delta\_t 直方图');
grid(ax2, 'on');

title(tl, sprintf('delta\\_t 诊断  |  后段帧 %d .. %d', ...
    FIRST_LATE_TIFF, FIRST_LATE_TIFF + N_compare - 1), 'FontSize', 11);

out_png = fullfile(SAVE_DIR, 'delta_t_diagnostic.png');
exportgraphics(fig, out_png, 'Resolution', 150);
fprintf('\n图像已保存：\n  %s\n', out_png);

%% ============================================================
%  9. 绘制 dt 对比图（SMA1 相邻差 vs TIFF 相邻差）
%% ============================================================
dt_sma1     = diff(sma1_t_late);    % [1 x N_SMA1_LATE-1]
dt_tiff_raw = diff(tiff_t_late);    % [1 x N_LATE-1]

% X 轴：sma1 会话时间作为共同时间基准
x_sma1 = sma1_t_late(1:end-1);

% TIFF x 轴：用初始偏移将相机时钟对齐到 Ripple 时钟（近似，忽略漂移）
init_offset = sma1_t_late(1) - tiff_t_late(1);
x_tiff = tiff_t_late(1:end-1) + init_offset;

% 裁剪 y 轴范围（超出的点仍画但被裁掉，数量会打印）
Y_LO = -2.5;
Y_HI =  2.5;
n_clip_sma1 = sum(dt_sma1 < Y_LO | dt_sma1 > Y_HI);
n_clip_tiff = sum(dt_tiff_raw < Y_LO | dt_tiff_raw > Y_HI);
if n_clip_sma1 > 0 || n_clip_tiff > 0
    fprintf('\n[dt 对比图] ylim 裁剪掉 %d 个 SMA1 点 和 %d 个 TIFF 点（超出 [%.1f, %.1f] s）\n', ...
        n_clip_sma1, n_clip_tiff, Y_LO, Y_HI);
end

% 异常判定阈值：dt > 0.12 s 或 dt < 0（时间倒退）
THRESH_HI = 0.12;
mask_sma1_anom = dt_sma1 > THRESH_HI | dt_sma1 < 0;
mask_tiff_anom = dt_tiff_raw > THRESH_HI | dt_tiff_raw < 0;

fig2 = figure('Color','w','Name','dt comparison','Position',[80 80 1400 520]);
ax3  = axes(fig2);
hold(ax3, 'on');

% 正常点（降采样 5x，浅色）
step_ds = 5;
plot(ax3, x_sma1(1:step_ds:end), dt_sma1(1:step_ds:end), '.', ...
    'Color', [0.6 0.75 1.0], 'MarkerSize', 2, 'DisplayName', 'dt\_sma1 (正常)');
plot(ax3, x_tiff(1:step_ds:end), dt_tiff_raw(1:step_ds:end), '.', ...
    'Color', [1.0 0.72 0.60], 'MarkerSize', 2, 'DisplayName', 'dt\_tiff (正常)');

% 异常点（全画，鲜明颜色 + 大点）
if any(mask_sma1_anom)
    plot(ax3, x_sma1(mask_sma1_anom), dt_sma1(mask_sma1_anom), 'ob', ...
        'MarkerSize', 7, 'MarkerFaceColor', 'b', 'LineWidth', 0.5, ...
        'DisplayName', sprintf('dt\\_sma1 异常 (N=%d)', sum(mask_sma1_anom)));
end
if any(mask_tiff_anom)
    plot(ax3, x_tiff(mask_tiff_anom), dt_tiff_raw(mask_tiff_anom), 'or', ...
        'MarkerSize', 5, 'MarkerFaceColor', 'r', 'LineWidth', 0.3, ...
        'DisplayName', sprintf('dt\\_tiff 异常 (N=%d)', sum(mask_tiff_anom)));
end

% 参考线
yline(ax3, 0.10, '--k', '0.1 s (正常帧间隔)', ...
    'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'bottom', ...
    'LineWidth', 0.8);
yline(ax3, THRESH_HI, ':k', sprintf('%.2f s (异常阈值)', THRESH_HI), ...
    'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'top', ...
    'LineWidth', 0.8);

xlabel(ax3, '会话时间 (s)');
ylabel(ax3, 'dt — 相邻帧时间差 (s)');
title(ax3, sprintf('SMA1 vs TIFF 相邻帧时间差对比  |  异常点：SMA1=%d  TIFF=%d', ...
    sum(mask_sma1_anom), sum(mask_tiff_anom)));
legend(ax3, 'Location', 'best');
grid(ax3, 'on');
ylim(ax3, [Y_LO, Y_HI]);

out_png2 = fullfile(SAVE_DIR, 'dt_comparison.png');
exportgraphics(fig2, out_png2, 'Resolution', 150);
fprintf('dt 对比图已保存：\n  %s\n', out_png2);

%% ============================================================
%  10. 保存
%% ============================================================
out_path = fullfile(SAVE_DIR, 'late_segment_timestamps.mat');
save(out_path, ...
    'tiff_t_late', ...              % [1 x N_LATE]       后段 TIFF 嵌入时间 (相机时钟, s)
    'sma1_t_late', ...              % [1 x N_SMA1_LATE]  后段 SMA1 触发时间 (Ripple 时钟, s)
    'delta_t', ...                  % [1 x N_compare]    tiff_t_late(i)-sma1_t_late(i)
    'unmatched_sma1_global_idx', ...% [1 x N_drop]       丢帧对应的 SMA1 全局编号
    'unmatched_sma1_time_s', ...    % [1 x N_drop]       丢帧对应的会话时间 (s)
    'FIRST_LATE_TIFF', 'N_SMA1', 'N_TIFF', 'MATCH_TOL_S', ...
    '-v7.3');
fprintf('\n结果已保存至：\n  %s\n', out_path);
fprintf('变量说明：\n');
fprintf('  tiff_t_late               — 后段每张 TIFF 的嵌入时间戳（相机时钟）\n');
fprintf('  sma1_t_late               — 后段每个 SMA1 触发的时间（Ripple 时钟）\n');
fprintf('  delta_t                   — tiff_t_late(i) - sma1_t_late(i)，按索引对齐相减\n');
fprintf('  unmatched_sma1_global_idx — 丢失 TIFF 对应的 SMA1 全局编号\n');
fprintf('  unmatched_sma1_time_s     — 丢失 TIFF 对应的会话时间\n');