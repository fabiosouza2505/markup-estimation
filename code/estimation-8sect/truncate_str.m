function str_trunc = truncate_str(str, max_len)
    %TRUNCATE_STR Trunca string para comprimento máximo
    if length(str) > max_len
        str_trunc = [str(1:max_len-3) '...'];
    else
        str_trunc = str;
    end
end
