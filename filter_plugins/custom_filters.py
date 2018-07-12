#!/usr/bin/python
class FilterModule(object):
    def filters(self):
        return {
            'increment_str': self.increment_str
        }
 
    def __increment_char(self, c):
        """
        Increment an uppercase character, returning 'a' if 'z' is given
        """
        return chr(ord(c) + 1) if c != 'z' else 'a'

    def increment_str(self, s):
        lpart = s.rstrip('z')
        num_replacements = len(s) - len(lpart)
        new_s = lpart[:-1] + self.__increment_char(lpart[-1]) if lpart else 'a'
        new_s += 'a' * num_replacements
        return new_s
