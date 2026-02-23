% v=zeros(432,738,360);
% parfor i =1:360
%     v = new_data.backward_stim(:,:,i);
%     for j = 1:432
%         for k = 1:768
%             if v(j,k,i)==127
%                 v(j,k,i) = 0;
%             end
%         end
%         print("j =",j);
%     end
%     new_data.backward_stim(:,:,i)=v;
% end
% nw_backward_stim = zeros(432,768,360)
for i =1:30
    i
    for j = 389:1:401
        for k = 378:1:390
            new_forward_stim(j,k,i) = 255;
        end
    end
end
% new_forward_stim = zeros(432,768,360)
% for i =1:360
%     i
%     for j = 1:432
%         for k = 1:768
%             if forward_stim(j,k,i)~=127
%                 new_forward_stim(j,k,i) = forward_stim(j,k,i);
%             end
%         end
%     end
% end
% 
% new_downward_stim = zeros(432,768,360)
% for i =1:360
%     i
%     for j = 1:432
%         for k = 1:768
%             if downward_stim(j,k,i)~=127
%                 new_downward_stim(j,k,i) = downward_stim(j,k,i);
%             end
%         end
%     end
% end
% 
% new_upward_stim = zeros(432,768,360)
% for i =1:360
%     i
%     for j = 1:432
%         for k = 1:768
%             if upward_stim(j,k,i)~=127
%                 new_upward_stim(j,k,i) = upward_stim(j,k,i);
%             end
%         end
%     end
% end
% 
% for i =1:360
%     for j = 1:432
%         for k = 1:768
%             if new_data.backward_stim(j,k,i)==127
%                 new_data.backward_stim(j,k,i) = 0;
%             end
%         end
%     end
% end