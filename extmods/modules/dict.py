def pair_to_dict(pair_sequence, key_name="key"):
    ret = []
    for k, v in pair_sequence:
        v["key"] = k
        ret.append(v)
    return ret
