package com.pgmanager.security;

import com.pgmanager.auth.UserLogin;
import com.pgmanager.auth.UserLoginRepository;
import com.pgmanager.party.PersonRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AppUserDetailsService implements UserDetailsService {
    private final UserLoginRepository userLoginRepository;
    private final PersonRepository personRepository;
    private static final Logger log = LoggerFactory.getLogger(AppUserDetailsService.class);


    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
    	log.info("username : {}", username);
        UserLogin user = userLoginRepository.findByUsername(username)
                .orElseThrow(() -> new UsernameNotFoundException("Invalid username"));
        String fullName = personRepository.findById(user.getPartyId())
                .map(p -> p.getFullName())
                .orElse(user.getUsername());
        return new AppUserPrincipal(
                user.getUserLoginId(),
                user.getPartyId(),
                user.getOrganizationId(),
                user.getUsername(),
                user.getPasswordHash(),
                user.getRoleTypeId(),
                user.getStatus(),
                fullName
        );
    }
}
